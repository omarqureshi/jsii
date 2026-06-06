import * as spec from '@jsii/spec';
import { toSnakeCase, toPascalCase } from 'codemaker';
import * as fs from 'fs-extra';
import * as path from 'path';

import { Generator, Legalese } from '../generator';
import { Target, TargetOptions } from '../target';
import { subprocess } from '../util';
import { VERSION } from '../version';
import { toReleaseVersion, toRubyVersionRange } from './version-utils';

import { TargetName } from './index';

export class RubyTarget extends Target {
  protected readonly generator: RubyGenerator;

  public constructor(options: TargetOptions) {
    super(options);
    this.generator = new RubyGenerator(options);
  }

  public async build(sourceDir: string, outDir: string): Promise<void> {
    const gemName = rubyGemName(this.assembly);

    // Package the generated files into a distributable .gem file
    await subprocess('gem', ['build', `${gemName}.gemspec`], {
      cwd: sourceDir,
    });

    // Copy compiled artifacts safely to the distribution directory
    await this.copyFiles(sourceDir, outDir);
  }
}

function rubyGemName(assembly: {
  name: string;
  targets?: spec.AssemblyTargets;
}): string {
  return (
    (assembly.targets?.ruby?.gem as string | undefined) ??
    assembly.name.replace('@', '').replace('/', '-')
  );
}

/**
 * Escape a string for use inside a Ruby double-quoted ("...") literal.
 * Handles backslash, double-quote, and `#` (otherwise `#{...}` would trigger
 * string interpolation).  Apply at every interpolation site that embeds a
 * jsii-supplied name into generated Ruby source.
 */
function rubyDq(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/#/g, '\\#');
}

/**
 * Escape a string for use inside a Ruby single-quoted ('...') literal.
 * Single-quoted strings only treat `\\` and `\'` specially.
 */
function rubySq(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

/**
 * Render a JS value as a Ruby expression that evaluates to JSON.parse of the
 * value's canonical JSON encoding.  Base64 keeps the embedded literal safe
 * from any input — no backslashes, quotes, `#{...}`, or newlines to escape.
 * Replaces the previous `%q{${JSON.stringify(...)}}` pattern, which silently
 * mangled any backslash in the JSON (Ruby's `%q{}` does not preserve `\\`).
 */
function rubyJsonLiteral(value: any): string {
  const json = JSON.stringify(value ?? { primitive: 'any' });
  const b64 = Buffer.from(json, 'utf-8').toString('base64');
  return `JSON.parse(Base64.strict_decode64("${b64}"))`;
}

/**
 * Whether a jsii member (method, property, or enum value) is marked
 * `@deprecated` in the source assembly.  Used by the collision-resolution
 * pass to pick a winning member when multiple snake_case to the same name.
 *
 * The reflect API exposes two shapes:
 *   - Plain spec objects (used by enum members `typeSpec.members`):
 *     `docs?.deprecated` is `string | undefined`.
 *   - `Documentable.docs` instances (used by `allProperties` / `allMethods`):
 *     `.docs.deprecated` is a boolean that also reflects the parent type's
 *     deprecation status.
 * We treat any truthy value on either shape as deprecated.
 */
function isDeprecated(member: { docs?: { deprecated?: unknown } }): boolean {
  return !!member.docs?.deprecated;
}

/**
 * Names that must be renamed (with a leading underscore) when used as Ruby
 * method/parameter identifiers.  Includes:
 *   - Ruby keywords (`end`, `class`, `def`, ...).  Using one as a method
 *     name produces a parse error.
 *   - The handful of Object methods the runtime hard-depends on
 *     (`send`, `__send__`) — without these the kernel can't dispatch back
 *     into a Ruby override.
 *   - Names the Ruby object model or the jsii runtime itself depends on:
 *     `initialize` (a member by that name would silently replace the
 *     generated constructor), `new` / `allocate` (class methods used to
 *     instantiate proxies — the registry hydrates refs via
 *     `klass.allocate`), `to_jsii` (struct serialization) and `ruby_class`
 *     (internal dispatch helper).
 *   - Additionally (not in this set — see `rubyName`): any name beginning
 *     with `jsii_` is prefixed, so generated members can never shadow the
 *     runtime's own API surface (`jsii_ref`, `jsii_serialize`,
 *     `jsii_call_method`, `jsii_properties`, ...), present or future.
 *
 * Other Object/Kernel methods (`method`, `methods`, `inspect`, `to_s`,
 * `hash`, ...) are deliberately NOT renamed: jsii-calc and real-world
 * assemblies use these names for legitimate JSII methods, and the
 * shadowing cost is mild (those methods are still reachable via
 * `Object.instance_method(:foo).bind(self).call(...)` or `__send__`).
 *
 * Must stay in sync with `Jsii::Utils::RUBY_RESERVED_NAMES` in
 * packages/@jsii/ruby-runtime/lib/jsii/utils.rb (enforced by a spec in
 * packages/@jsii/ruby-runtime-test/spec/unit/utils_spec.rb), so kernel
 * callbacks dispatch to the renamed member.
 */
const RUBY_RESERVED_NAMES = new Set([
  // Keywords
  'alias',
  'and',
  'begin',
  'break',
  'case',
  'class',
  'def',
  'defined?',
  'do',
  'else',
  'elsif',
  'end',
  'ensure',
  'false',
  'for',
  'if',
  'in',
  'module',
  'next',
  'nil',
  'not',
  'or',
  'redo',
  'rescue',
  'retry',
  'return',
  'self',
  'super',
  'then',
  'true',
  'undef',
  'unless',
  'until',
  'when',
  'while',
  'yield',
  // Hard runtime dependencies (callbacks use `__send__` for dispatch).
  'send',
  '__send__',
  // Ruby object-model / jsii-runtime hooks (see doc comment above).
  'initialize',
  'new',
  'allocate',
  'to_jsii',
  'ruby_class',
]);

export class RubyGenerator extends Generator {
  public constructor(options: TargetOptions) {
    super({ runtimeTypeChecking: options.runtimeTypeChecking });
    // Ruby convention is 2-space indentation (CodeMaker defaults to 4).
    this.code.indentation = 2;
  }

  /**
   * Normalize a type reference to its raw `spec.TypeReference` shape.
   * Call sites hold two shapes: jsii-reflect `TypeReference` instances
   * (which wrap the raw spec under `.spec`) for members coming off
   * `allProperties` / `allMethods`, and raw spec objects for
   * `typeSpec.spec.initializer.parameters`.  Collection/union introspection
   * only works on the raw shape.
   */
  private typeRefSpec(type: any): spec.TypeReference | undefined {
    return type?.spec ?? type;
  }

  private isStructFqn(fqn: string): boolean {
    const type = this.reflectAssembly.system.tryFindFqn(fqn);
    return !!(type?.isInterfaceType() && type?.isDataType());
  }

  public async save(outdir: string, tarball: string, legalese: Legalese) {
    const assembly = this.reflectAssembly;

    // Define the output path for the main Ruby library file
    const srcFile = path.join('lib', `${assembly.name}.rb`);
    this.code.openFile(srcFile);

    // Emit the core runtime dependency requirement
    this.emitHeader();

    // Pre-declare external dependencies to avoid NameErrors before opening our main module
    const dependencies = Object.keys(assembly.spec.dependencies ?? {});
    this.emitDependencies(dependencies);

    const assemblyModule = this.rubyModuleForAssembly(assembly.name);
    const moduleParts = assemblyModule.split('::');
    let currentModule = '';
    for (const part of moduleParts) {
      currentModule = currentModule ? `${currentModule}::${part}` : part;
      this.code.line(`module ${currentModule}; end`);
    }

    this.code.open(`module ${assemblyModule}`);

    // Load assembly dynamically
    const tarballName = this.getAssemblyFileName();
    this.code.line(
      `Jsii::Assembly.load('${rubySq(assembly.name)}', '${rubySq(assembly.version)}', File.expand_path('${rubySq(tarballName)}', __dir__))`,
    );
    this.code.line('');

    // Pre-declare local JSII namespaces
    const classRubyPaths = this.collectClassRubyPaths();
    this.emitLocalNamespacePredeclarations(classRubyPaths);

    // Loop through the Abstract Syntax Tree (AST) metadata types
    const types = assembly.allTypes.slice();
    const sortedTypes: any[] = [];
    const visited = new Set<string>();

    const visit = (type: any) => {
      if (visited.has(type.fqn)) return;
      visited.add(type.fqn);

      // Visit base class
      if (type.isClassType() && type.spec.base) {
        const base = assembly.allTypes.find((t) => t.fqn === type.spec.base);
        if (base) visit(base);
      }

      // Visit implemented interfaces
      const interfaces =
        type.isClassType() || type.isInterfaceType()
          ? (type.spec.interfaces ?? [])
          : [];
      for (const ifaceFqn of interfaces) {
        const iface = assembly.allTypes.find((t) => t.fqn === ifaceFqn);
        if (iface) visit(iface);
      }

      // Visit declaring parent for nested types
      const fqnParts = type.fqn.split('.');
      if (fqnParts.length > 2) {
        const parentFqn = fqnParts.slice(0, -1).join('.');
        const parentType = assembly.allTypes.find((t) => t.fqn === parentFqn);
        if (parentType) visit(parentType);
      }

      sortedTypes.push(type);
    };

    for (const type of types) {
      visit(type);
    }

    for (const type of sortedTypes) {
      const fullNamespace = this.relativeRubyNamespace(type.fqn);
      const prefix = fullNamespace ? `${fullNamespace}::` : '';

      if (type.isEnumType()) {
        this.emitEnumType(type, prefix);
      }

      if (type.isInterfaceType()) {
        this.emitInterfaceType(type, prefix);
      }

      if (type.isClassType()) {
        this.emitClassType(type, prefix);
      }
    }

    this.code.close('end');

    this.code.closeFile(srcFile);

    // Generate the gemspec manifest file for package management
    await this.generateGemspec(outdir);

    return super.save(outdir, tarball, legalese);
  }

  private emitHeader(): void {
    this.code.line("require 'jsii'");
    this.code.line("require 'json'");
    this.code.line("require 'base64'");
    this.code.line('');
  }

  private emitDependencies(dependencies: string[]): void {
    for (const dep of dependencies) {
      this.code.line(`require '${rubySq(dep)}'`);
    }
    if (dependencies.length > 0) {
      this.code.line('');
    }

    const preDeclaredRubyModules = new Set<string>();
    for (const dep of dependencies) {
      const moduleName = this.rubyModuleForAssembly(dep);
      let current = '';
      for (const part of moduleName.split('::')) {
        current = current ? `${current}::${part}` : part;
        preDeclaredRubyModules.add(current);
      }
    }
    for (const mod of Array.from(preDeclaredRubyModules).sort(
      (a, b) => a.split('::').length - b.split('::').length,
    )) {
      this.code.line(`module ${mod}; end`);
    }
  }

  private emitLocalNamespacePredeclarations(classRubyPaths: Set<string>): void {
    const pureRubyNamespaces = new Set<string>();

    for (const type of this.reflectAssembly.allTypes) {
      if (!type.namespace) continue;

      const relNamespace = this.relativeRubyNamespace(type.fqn);
      if (!relNamespace) continue;

      let current = '';
      for (const part of relNamespace.split('::')) {
        current = current ? `${current}::${part}` : part;
        if (classRubyPaths.has(current)) continue;
        pureRubyNamespaces.add(current);
      }
    }

    const sortedNamespaces = Array.from(pureRubyNamespaces).sort(
      (a, b) => a.split('::').length - b.split('::').length,
    );

    for (const ns of sortedNamespaces) {
      this.code.line(`module ${ns}; end`);
    }
    this.code.line('');
  }

  private emitEnumType(typeSpec: any, prefix: string): void {
    const resolvedMembers = this.dedupByRubyName(
      (typeSpec.members ?? []) as any[],
      (m: any) => this.rubyConstName(m.name),
      typeSpec.fqn,
    );
    this.code.open(`module ${prefix}${this.rubyModuleName(typeSpec.name)}`);
    for (const member of resolvedMembers) {
      this.code.line(
        `${this.rubyConstName(member.name)} = Jsii::Enum.new("${rubyDq(typeSpec.fqn)}", "${rubyDq(member.name)}")`,
      );
    }
    this.code.close('end');
    this.code.line('');
  }

  private emitInterfaceType(typeSpec: any, prefix: string): void {
    const resolvedAllProperties = this.dedupByRubyName(
      typeSpec.allProperties as any[],
      (p: any) => this.rubyName(p.name),
      typeSpec.fqn,
    );
    const resolvedAllMethods = this.dedupByRubyName(
      typeSpec.allMethods as any[],
      (m: any) => this.rubyName(m.name),
      typeSpec.fqn,
    );
    const kind = typeSpec.datatype ? 'class' : 'module';
    const rubyName = this.rubyModuleName(typeSpec.name);

    const bases = typeSpec.spec.interfaces ?? [];
    const baseMixins = bases.map((b: any) => `::${this.rubyFullTypeName(b)}`);
    // JSII structs may extend several parents (diamond hierarchies), but a
    // Ruby class has a single superclass: subclass the first parent and
    // record the rest via `jsii_extra_struct_bases` so is_a?/kind_of?/case
    // dispatch honor every declared parent (see Jsii::Struct).  Members are
    // unaffected either way — allProperties flattens the full hierarchy.
    const baseString =
      typeSpec.datatype && bases.length > 0
        ? ` < ${baseMixins[0]}`
        : typeSpec.datatype
          ? ' < Jsii::Struct'
          : '';

    this.code.open(`${kind} ${prefix}${rubyName}${baseString}`);

    if (!typeSpec.datatype) {
      for (const mixin of baseMixins) {
        this.code.line(`include ${mixin}`);
      }
    }

    this.code.line(
      `Jsii::Object.register_jsii_fqn("${rubyDq(typeSpec.fqn)}", self)`,
    );
    if (typeSpec.datatype && baseMixins.length > 1) {
      this.code.line(
        `jsii_extra_struct_bases.push(${baseMixins.slice(1).join(', ')})`,
      );
    }
    this.code.line('');

    if (typeSpec.datatype) {
      const props = resolvedAllProperties;

      const initArgs = props
        .map((p: any) => {
          const name = this.rubyName(p.name);
          return p.optional ? `${name}: nil` : `${name}:`;
        })
        .join(', ');

      this.code.open(`def initialize(${initArgs})`);
      for (const prop of props) {
        const rubyName = this.rubyName(prop.name);
        this.emitStructCoercion(rubyName, prop.type, {
          assignment: `@${rubyName}`,
        });
        // Validate the (coerced) member value — structs are the main
        // vehicle for user-supplied data, so they get the same runtime
        // type checking as method/constructor parameters.
        this.emitTypeChecking(`@${rubyName}`, prop.type, prop.name, {
          isOptional: prop.optional,
        });
      }
      this.code.close('end');
      this.code.line('');

      for (const prop of props) {
        this.code.line(`attr_reader :${this.rubyName(prop.name)}`);
      }
      this.code.line('');

      this.code.open('def self.jsii_properties');
      this.code.open('{');
      for (const prop of props) {
        this.code.line(
          `:${this.rubyName(prop.name)} => "${rubyDq(prop.name)}",`,
        );
      }
      this.code.close('}');
      this.code.close('end');
      this.code.line('');

      this.code.open('def to_jsii');
      this.code.line('result = {}');
      if (bases.length > 0) {
        this.code.line('result.merge!(super)');
      }
      this.code.open('result.merge!({');
      for (const prop of props) {
        this.code.line(
          `"${rubyDq(prop.name)}" => @${this.rubyName(prop.name)},`,
        );
      }
      this.code.close('})');
      this.code.line('result.compact');
      this.code.close('end');
    } else {
      for (const prop of resolvedAllProperties) {
        const propRubyName = this.rubyName(prop.name);
        this.code.open(`def ${propRubyName}()`);
        this.code.line(`jsii_get_property("${rubyDq(prop.name)}")`);
        this.code.close(`end`);
        this.code.line('');
        if (!prop.immutable) {
          this.code.open(`def ${propRubyName}=(value)`);
          this.emitStructCoercion('value', prop.type);
          this.emitTypeChecking('value', prop.type, prop.name, {
            isOptional: prop.optional,
          });
          this.code.line(`jsii_set_property("${rubyDq(prop.name)}", value)`);
          this.code.close('end');
          this.code.line('');
        }
      }

      for (const method of resolvedAllMethods) {
        const sigParams = method.parameters
          .map((p: any) => {
            const rubyParam = this.rubyName(p.name);
            if (p.variadic) return `*${rubyParam}`;
            return p.optional ? `${rubyParam} = nil` : rubyParam;
          })
          .join(', ');
        const callParams = method.parameters
          .map((p: any) => {
            const rubyParam = this.rubyName(p.name);
            if (p.variadic) return `*${rubyParam}`;
            return rubyParam;
          })
          .join(', ');
        this.code.open(`def ${this.rubyName(method.name)}(${sigParams})`);
        for (const p of method.parameters) {
          const rubyParam = this.rubyName(p.name);
          this.emitStructCoercion(rubyParam, p.type, {
            variadic: p.variadic,
          });
          this.emitTypeChecking(rubyParam, p.type, p.name, {
            isOptional: p.optional,
            isVariadic: p.variadic,
          });
        }
        if (method.async) {
          this.code.line(
            `jsii_async_call_method("${rubyDq(method.name)}", [${callParams}])`,
          );
        } else {
          this.code.line(
            `jsii_call_method("${rubyDq(method.name)}", [${callParams}])`,
          );
        }
        this.code.close('end');
        this.code.line('');
      }

      this.code.open('def self.jsii_overridable_methods');
      this.code.open('{');
      for (const prop of resolvedAllProperties) {
        const isOptional = prop.optional ? 'true' : 'false';
        this.code.line(
          `:${this.rubyName(prop.name)} => { kind: :property, name: "${rubyDq(prop.name)}", is_optional: ${isOptional} },`,
        );
      }
      for (const method of resolvedAllMethods) {
        this.code.line(
          `:${this.rubyName(method.name)} => { kind: :method, name: "${rubyDq(method.name)}", is_optional: false },`,
        );
      }
      this.code.close('}');
      this.code.close('end');
    }

    this.code.close('end');
    this.code.line('');
  }

  private emitClassType(typeSpec: any, prefix: string): void {
    const resolvedAllProperties = this.dedupByRubyName(
      typeSpec.allProperties as any[],
      (p: any) => this.rubyPropertyName(p),
      typeSpec.fqn,
    );
    const resolvedAllMethods = this.dedupByRubyName(
      typeSpec.allMethods as any[],
      (m: any) => this.rubyMethodName(m),
      typeSpec.fqn,
    );
    const rubyName = this.rubyModuleName(typeSpec.name);

    const baseFqn = typeSpec.spec.base;
    let baseClass = 'Jsii::Object';
    if (baseFqn) {
      baseClass = `::${this.rubyFullTypeName(baseFqn)}`;
    }

    const interfaces = typeSpec.spec.interfaces ?? [];
    const interfaceMixins = interfaces.map(
      (i: any) => `::${this.rubyFullTypeName(i)}`,
    );

    this.code.open(`class ${prefix}${rubyName} < ${baseClass}`);

    for (const mixin of interfaceMixins) {
      this.code.line(`include ${mixin}`);
    }
    this.code.line(`self.jsii_fqn = "${rubyDq(typeSpec.fqn)}"`);
    this.code.line(
      `Jsii::Object.register_jsii_fqn("${rubyDq(typeSpec.fqn)}", self)`,
    );
    this.code.line('');

    const initializer = typeSpec.spec.initializer;
    if (
      initializer &&
      initializer.parameters &&
      initializer.parameters.length > 0
    ) {
      const initParams = initializer.parameters
        .map((p: any) => {
          const rubyParam = this.rubyName(p.name);
          if (p.variadic) return `*${rubyParam}`;
          return p.optional ? `${rubyParam} = nil` : rubyParam;
        })
        .join(', ');

      this.code.open(`def initialize(${initParams})`);
      for (const p of initializer.parameters) {
        const rubyParam = this.rubyName(p.name);
        this.emitStructCoercion(rubyParam, p.type);
      }
      const superArgs = initializer.parameters
        .map((p: any) => {
          const rubyParam = this.rubyName(p.name);
          if (p.variadic) return `*${rubyParam}`;
          return rubyParam;
        })
        .join(', ');

      for (const p of initializer.parameters) {
        const rubyParam = this.rubyName(p.name);
        this.emitTypeChecking(rubyParam, p.type, p.name, {
          isOptional: p.optional,
          isVariadic: p.variadic,
        });
      }

      this.code.line(
        `Jsii::Object.instance_method(:initialize).bind(self).call(${superArgs})`,
      );
      this.code.close('end');
    } else {
      this.code.open('def initialize(*args)');
      this.code.line(
        'Jsii::Object.instance_method(:initialize).bind(self).call(*args)',
      );
      this.code.close('end');
    }
    this.code.line('');

    // Static members are emitted only on their *defining* class.  Ruby
    // inherits singleton methods, which matches the ES6 static-inheritance
    // semantics the kernel implements (its method/property lookups walk the
    // base chain, and the base's stub carries the base fqn).  Re-emitting an
    // inherited static here would bake the *derived* fqn into the kernel
    // call instead.  A child that overrides a static still gets its own
    // stub, because allMethods/allProperties yield the most-derived
    // declaration (see the StaticHelloParent/Child fixture in jsii-calc).
    const isOwnStatic = (m: any) => m.definingType?.fqn === typeSpec.fqn;

    const overridableMethods = resolvedAllMethods.filter((m: any) => !m.static);
    const overridableProps = resolvedAllProperties.filter(
      (p: any) => !p.static,
    );

    this.code.open('def self.jsii_overridable_methods');
    this.code.open('{');
    for (const prop of overridableProps) {
      const rubyName = this.rubyName(prop.name);
      const isOptional = prop.optional ? 'true' : 'false';
      this.code.line(
        `:${rubyName} => { kind: :property, name: "${rubyDq(prop.name)}", is_optional: ${isOptional} },`,
      );
    }
    for (const method of overridableMethods) {
      const rubyName = this.rubyName(method.name);
      this.code.line(
        `:${rubyName} => { kind: :method, name: "${rubyDq(method.name)}", is_optional: false },`,
      );
    }
    this.code.close('}');
    this.code.close('end');
    this.code.line('');

    for (const method of resolvedAllMethods) {
      if (!method.static || !isOwnStatic(method)) continue;

      const sigParams = method.parameters
        .map((p: any) => {
          const rubyParam = this.rubyName(p.name);
          if (p.variadic) return `*${rubyParam}`;
          return p.optional ? `${rubyParam} = nil` : rubyParam;
        })
        .join(', ');

      const callParams = method.parameters
        .map((p: any) => {
          const rubyParam = this.rubyName(p.name);
          if (p.variadic) return `*${rubyParam}`;
          return rubyParam;
        })
        .join(', ');

      this.code.open(`def self.${this.rubyMethodName(method)}(${sigParams})`);
      for (const p of method.parameters) {
        const rubyParam = this.rubyName(p.name);
        this.emitStructCoercion(rubyParam, p.type, {
          variadic: p.variadic,
        });
        this.emitTypeChecking(rubyParam, p.type, p.name, {
          isOptional: p.optional,
          isVariadic: p.variadic,
        });
      }
      this.code.line(
        `Jsii::Kernel.instance.call_static("${rubyDq(typeSpec.fqn)}", "${rubyDq(method.name)}", [${callParams}])`,
      );
      this.code.close('end');
      this.code.line('');
    }

    for (const prop of resolvedAllProperties) {
      if (prop.static && !isOwnStatic(prop)) continue;

      const rubyName = this.rubyPropertyName(prop);

      if (prop.static) {
        this.code.open(`def self.${rubyName}()`);
        this.code.line(
          `Jsii::Kernel.instance.get_static("${rubyDq(typeSpec.fqn)}", "${rubyDq(prop.name)}")`,
        );
        this.code.close(`end`);
        this.code.line('');

        if (!prop.immutable) {
          this.code.open(`def self.${rubyName}=(value)`);
          this.emitStructCoercion('value', prop.type);
          this.emitTypeChecking('value', prop.type, prop.name, {
            isOptional: prop.optional,
          });
          this.code.line(
            `Jsii::Kernel.instance.set_static("${rubyDq(typeSpec.fqn)}", "${rubyDq(prop.name)}", value)`,
          );
          this.code.close('end');
          this.code.line('');
        }
      } else {
        this.code.open(`def ${rubyName}()`);
        this.code.line(`jsii_get_property("${rubyDq(prop.name)}")`);
        this.code.close(`end`);
        this.code.line('');

        if (!prop.immutable) {
          this.code.open(`def ${rubyName}=(value)`);
          this.emitStructCoercion('value', prop.type);
          this.emitTypeChecking('value', prop.type, prop.name, {
            isOptional: prop.optional,
          });
          this.code.line(`jsii_set_property("${rubyDq(prop.name)}", value)`);
          this.code.close('end');
          this.code.line('');
        }
      }
    }

    for (const method of resolvedAllMethods) {
      if (method.static) continue;

      const sigParams = method.parameters
        .map((p: any) => {
          const rubyParam = this.rubyName(p.name);
          if (p.variadic) return `*${rubyParam}`;
          return p.optional ? `${rubyParam} = nil` : rubyParam;
        })
        .join(', ');

      const callParams = method.parameters
        .map((p: any) => {
          const rubyParam = this.rubyName(p.name);
          if (p.variadic) return `*${rubyParam}`;
          return rubyParam;
        })
        .join(', ');

      this.code.open(`def ${this.rubyMethodName(method)}(${sigParams})`);
      for (const p of method.parameters) {
        const rubyParam = this.rubyName(p.name);
        this.emitStructCoercion(rubyParam, p.type, {
          variadic: p.variadic,
        });
        this.emitTypeChecking(rubyParam, p.type, p.name, {
          isOptional: p.optional,
          isVariadic: p.variadic,
        });
      }
      if (method.async) {
        this.code.line(
          `jsii_async_call_method("${rubyDq(method.name)}", [${callParams}])`,
        );
      } else {
        this.code.line(
          `jsii_call_method("${rubyDq(method.name)}", [${callParams}])`,
        );
      }
      this.code.close('end');
      this.code.line('');
    }

    this.code.close('end');
    this.code.line('');
  }

  private rubyFullTypeName(fqn: string): string {
    if (fqn === 'any') return 'Object';

    const segments = fqn.split('.');
    const assemblyName = segments[0];
    const config =
      assemblyName === this.assembly.name
        ? this.assembly
        : this.assembly.dependencyClosure?.[assemblyName];

    if (!config) {
      const assemblyModule = this.rubyModuleName(assemblyName);
      return [
        assemblyModule,
        ...segments.slice(1).map((p) => this.rubyModuleName(p)),
      ].join('::');
    }

    const assemblyModule =
      config.targets?.ruby?.module ?? this.rubyModuleName(assemblyName);
    const result = [];

    for (let len = segments.length; len > 0; len--) {
      const submoduleFqn = segments.slice(0, len).join('.');

      if (submoduleFqn === assemblyName) {
        result.unshift(assemblyModule);
        break;
      }

      const submoduleConfig = config.submodules?.[submoduleFqn];
      const explicitModule = submoduleConfig?.targets?.ruby?.module;

      if (explicitModule) {
        result.unshift(explicitModule);
        break;
      }

      result.unshift(this.rubyModuleName(segments[len - 1]));
    }

    return result.join('::');
  }

  private relativeRubyNamespace(fqn: string): string {
    const full = this.rubyFullTypeName(fqn).split('::');
    const asm = this.rubyModuleForAssembly(fqn.split('.')[0]).split('::');
    return full.slice(asm.length, -1).join('::');
  }

  /**
   * Compute the set of Ruby paths (relative to the assembly module) that
   * will be declared as Ruby classes — jsii classes plus jsii interfaces
   * marked `datatype: true` (which generate as Ruby classes inheriting from
   * `Jsii::Struct`).  Used to suppress conflicting `module X; end`
   * pre-declarations of namespace fragments that share a Ruby name with a
   * class.
   */
  private collectClassRubyPaths(): Set<string> {
    const paths = new Set<string>();
    for (const type of this.reflectAssembly.allTypes) {
      const isClassEmit =
        type.isClassType() || (type.isInterfaceType() && type.spec.datatype);
      if (!isClassEmit) continue;

      const namespacePart = this.relativeRubyNamespace(type.fqn);
      const namePart = this.rubyModuleName(type.name);
      paths.add(namespacePart ? `${namespacePart}::${namePart}` : namePart);
    }
    return paths;
  }

  private rubyName(name: string): string {
    const snake = toSnakeCase(name);
    if (RUBY_RESERVED_NAMES.has(snake)) {
      return `_${snake}`;
    }
    // The `jsii_` prefix is reserved for the runtime's own API surface
    // (`jsii_ref`, `jsii_serialize`, `jsii_call_method`, ...) — prefix any
    // member that would land in it so generated code can never shadow a
    // runtime method, present or future.
    if (snake.startsWith('jsii_')) {
      return `_${snake}`;
    }
    // Names starting with a digit are invalid Ruby identifiers.
    if (/^\d/.test(snake)) {
      return `_${snake}`;
    }
    return snake;
  }

  /**
   * Build a Ruby expression that coerces plain Hashes into struct instances
   * anywhere a struct can appear inside `ref` — directly, as the element
   * type of an array/map (recursively), or as the single unambiguous struct
   * arm of a union.  Returns `undefined` when `ref` cannot contain a
   * coercible struct, so call sites can skip emission entirely.
   *
   * Coercion matters beyond ergonomics: an uncoerced Hash serializes with
   * its literal (snake_case) keys, while the kernel expects the struct's
   * camelCase wire form — so a Hash that misses coercion is silent wire
   * corruption, not a graceful fallback.
   *
   * Union rule: coerce only when exactly one arm is a struct AND no other
   * arm could legitimately be satisfied by a Hash (a map arm, or an
   * any/json arm) — otherwise the Hash is ambiguous and is passed through
   * unchanged for the runtime/kernel to interpret.
   *
   * Block parameters are named `jsii_v<depth>` — the `jsii_` prefix is
   * reserved (see RUBY_RESERVED_NAMES), so they can never collide with or
   * shadow a generated parameter name.
   */
  private coercionExpr(
    valueExpr: string,
    ref: spec.TypeReference | undefined,
    depth = 0,
  ): string | undefined {
    if (!ref) {
      return undefined;
    }

    if (spec.isNamedTypeReference(ref)) {
      if (!this.isStructFqn(ref.fqn)) {
        return undefined;
      }
      return this.structFromHashExpr(valueExpr, ref.fqn);
    }

    if (spec.isCollectionTypeReference(ref)) {
      const blockVar = `jsii_v${depth}`;
      const inner = this.coercionExpr(
        blockVar,
        ref.collection.elementtype,
        depth + 1,
      );
      if (!inner) {
        return undefined;
      }
      if (ref.collection.kind === spec.CollectionKind.Array) {
        return `${valueExpr}.is_a?(Array) ? ${valueExpr}.map { |${blockVar}| ${inner} } : ${valueExpr}`;
      }
      return `${valueExpr}.is_a?(Hash) ? ${valueExpr}.transform_values { |${blockVar}| ${inner} } : ${valueExpr}`;
    }

    if (spec.isUnionTypeReference(ref)) {
      const structArms = ref.union.types.filter(
        (t) => spec.isNamedTypeReference(t) && this.isStructFqn(t.fqn),
      ) as spec.NamedTypeReference[];
      const hashAmbiguous = ref.union.types.some(
        (t) =>
          (spec.isCollectionTypeReference(t) &&
            t.collection.kind === spec.CollectionKind.Map) ||
          (spec.isPrimitiveTypeReference(t) &&
            (t.primitive === spec.PrimitiveType.Any ||
              t.primitive === spec.PrimitiveType.Json)),
      );
      if (structArms.length === 1 && !hashAmbiguous) {
        return this.structFromHashExpr(valueExpr, structArms[0].fqn);
      }
      return undefined;
    }

    return undefined;
  }

  /**
   * Ruby expression coercing `valueExpr` into the struct `fqn` when it is a
   * Hash, passing anything else through.  Keys are symbolized before the
   * keyword splat: `**` requires Symbol keys, and JSON-shaped hashes carry
   * String keys — without `transform_keys` those raise a bare
   * `ArgumentError: wrong number of arguments` instead of constructing the
   * struct.  (Symbol keys pass through `to_sym` unchanged; unknown keys
   * still surface as Ruby's clear "unknown keyword" ArgumentError.)
   */
  private structFromHashExpr(valueExpr: string, fqn: string): string {
    const structType = this.rubyFullTypeName(fqn);
    return `${valueExpr}.is_a?(Hash) ? ::${structType}.new(**${valueExpr}.transform_keys(&:to_sym)) : ${valueExpr}`;
  }

  private emitStructCoercion(
    variableName: string,
    type: any,
    options: { variadic?: boolean; assignment?: string } = {},
  ): void {
    const ref = this.typeRefSpec(type);

    if (options.variadic) {
      // For variadic parameters, `ref` is the element type already.
      const inner = this.coercionExpr('jsii_v0', ref, 1);
      if (inner) {
        this.code.line(`${variableName}.map! { |jsii_v0| ${inner} }`);
      }
      return;
    }

    const expr = this.coercionExpr(variableName, ref);
    if (!expr) {
      if (options.assignment) {
        this.code.line(`${options.assignment} = ${variableName}`);
      }
      return;
    }
    this.code.line(`${options.assignment ?? variableName} = ${expr}`);
  }

  private emitTypeChecking(
    variableName: string,
    type: any,
    jsiiName: string,
    options: { isOptional?: boolean; isVariadic?: boolean } = {},
  ): void {
    if (!this.runtimeTypeChecking) {
      return;
    }

    // Normalize: initializer parameters carry raw spec type refs (no
    // `.spec`); reflect members wrap theirs.  Reading `.spec`
    // unconditionally made every constructor check validate against
    // `{primitive: 'any'}` — i.e. check nothing.
    const refSpec = this.typeRefSpec(type);

    if (options.isVariadic) {
      this.code.open(`${variableName}.each_with_index do |item, index|`);
      this.code.line(
        `Jsii::Type.check_type(item, ${rubyJsonLiteral(
          refSpec,
        )}, "${rubyDq(jsiiName)}[#{index}]")`,
      );
      this.code.close(`end`);
    } else {
      this.code.line(
        `Jsii::Type.check_type(${variableName}, ${rubyJsonLiteral(
          refSpec,
        )}, "${rubyDq(jsiiName)}")${options.isOptional ? ` unless ${variableName}.nil?` : ''}`,
      );
    }
  }

  /**
   * Emit-name for a property, accounting for the JSII `const: true` flag.
   * Const properties take an UPPER_SNAKE_CASE form (`maybeList` → `MAYBE_LIST`,
   * `PROPERTY` stays `PROPERTY`) — both idiomatic for Ruby constants and
   * distinct from any sibling snake_case property's lowercased name.
   * This matches Python's `toPythonPropertyName(name, constant=true)` which
   * uppercases the snake_case form for the same reason.
   *
   * Ruby parses `Foo.PROPERTY` and `Foo.property` as distinct method calls,
   * so both can coexist on the same class without ambiguity.
   */
  private rubyPropertyName(prop: { name: string; const?: boolean }): string {
    if (prop.const) return this.rubyConstName(prop.name);
    return this.rubyName(prop.name);
  }

  private rubyMethodName(method: { name: string }): string {
    return this.rubyName(method.name);
  }

  /**
   * Filter a member list to resolve Ruby-name collisions.  When two members
   * map to the same Ruby identifier, drop deprecated members; if exactly
   * one non-deprecated member survives, use it.  Throws if all colliding
   * members are deprecated, or if more than one non-deprecated member
   * remains (a generator bug — these cases shouldn't reach this point).
   *
   * Mirrors Python's `prepareMembers`.  See
   * https://github.com/aws/jsii/issues/2508 for the motivating fixture.
   */
  private dedupByRubyName<
    T extends { name: string; docs?: { deprecated?: string } },
  >(members: readonly T[], rubyName: (m: T) => string, fqn: string): T[] {
    const byName = new Map<string, T[]>();
    for (const m of members) {
      const key = rubyName(m);
      const bucket = byName.get(key) ?? [];
      bucket.push(m);
      byName.set(key, bucket);
    }

    const out: T[] = [];
    for (const [rubyKey, bucket] of byName) {
      if (bucket.length === 1) {
        out.push(bucket[0]);
        continue;
      }
      const nonDeprecated = bucket.filter((m) => !isDeprecated(m));
      if (nonDeprecated.length === 0) {
        throw new Error(
          `All members mapping to Ruby name '${rubyKey}' on ${fqn} are ` +
            `deprecated; cannot pick a winner.  jsii names: ${bucket
              .map((m) => `'${m.name}'`)
              .join(', ')}`,
        );
      }
      if (nonDeprecated.length > 1) {
        throw new Error(
          `Multiple non-deprecated members map to Ruby name '${rubyKey}' ` +
            `on ${fqn}: ${nonDeprecated
              .map((m) => `'${m.name}'`)
              .join(
                ', ',
              )}.  Mark all but one deprecated (or rename) to disambiguate.`,
        );
      }
      out.push(nonDeprecated[0]);
    }
    return out;
  }

  private rubyModuleForAssembly(name: string): string {
    if (name === this.assembly.name) {
      return this.assembly.targets?.ruby?.module ?? this.rubyModuleName(name);
    }
    const depInfo = this.assembly.dependencyClosure?.[name];
    if (depInfo) {
      return depInfo.targets?.ruby?.module ?? this.rubyModuleName(name);
    }
    return this.rubyModuleName(name);
  }

  private rubyModuleName(name: string): string {
    const acronyms = [
      ...(this.assembly.targets?.ruby?.acronyms ?? []),
      ...Object.values(this.assembly.dependencyClosure ?? {}).flatMap(
        (dep: any) => dep.targets?.ruby?.acronyms ?? [],
      ),
    ];

    // Handle scoped packages: @scope/package -> Scope::Package
    if (name.startsWith('@')) {
      const parts = name.slice(1).split('/');
      return parts.map((p) => this.rubyModuleName(p)).join('::');
    }

    // Handle hyphens: jsii-calc -> JsiiCalc
    if (name.includes('-')) {
      const parts = name.split('-');
      return parts.map((p) => this.rubyModuleName(p)).join('');
    }

    const sanitized = name.replace(/[^a-zA-Z0-9_]/g, '');
    let pascal =
      sanitized.charAt(0) === sanitized.charAt(0).toUpperCase()
        ? sanitized
        : toPascalCase(sanitized);

    for (const acronym of acronyms) {
      // Find the acronym case-insensitively. A match is only considered a valid
      // word boundary if it starts with a capital letter and is followed by either
      // another capital letter, a digit, an 's' (for plurals), or the end of the string.
      const regex = new RegExp(`(${acronym})`, 'ig');
      pascal = pascal.replace(regex, (match, _p1, offset) => {
        if (match[0] !== match[0].toUpperCase()) return match;

        const nextChar = pascal[offset + match.length];
        if (nextChar) {
          // Must be uppercase, digit, or 's' followed by uppercase, digit, or end of string
          const isValid =
            /^[A-Z0-9]$/.test(nextChar) ||
            (nextChar === 's' &&
              (!pascal[offset + match.length + 1] ||
                /^[A-Z0-9]$/.test(pascal[offset + match.length + 1])));
          if (!isValid) return match;
        }

        return acronym;
      });
    }

    return pascal;
  }

  private rubyConstName(name: string): string {
    const constName = toSnakeCase(name)
      .toUpperCase()
      .replace(/[^A-Z0-9_]/g, '_');
    if (/^[0-9]/.test(constName)) {
      return `V_${constName}`;
    }
    return constName;
  }

  private async generateGemspec(outdir: string) {
    const assembly = this.reflectAssembly;
    const gemName = rubyGemName(assembly.spec);
    const gemspecPath = path.join(outdir, `${gemName}.gemspec`);
    await fs.mkdir(outdir, { recursive: true });

    const gemspecContent = [
      `Gem::Specification.new do |s|`,
      `  s.name        = '${rubySq(gemName)}'`,
      `  s.version     = '${rubySq(toReleaseVersion(assembly.version, TargetName.RUBY))}'`,
      `  s.summary     = 'Ruby bindings for ${rubySq(assembly.name)}'`,
      `  s.authors     = ['JSII Generator']`,
      `  s.files       = Dir["lib/**/*"]`,
      `  s.required_ruby_version = '>= 3.1.0'`,
      `  s.add_runtime_dependency 'jsii-ruby-runtime', ${toRubyVersionRange(`^${VERSION}`)}`,
      `  s.add_runtime_dependency 'base64', '~> 0.2', '>= 0.2.0'`,
    ];

    if (this.assembly.dependencies) {
      for (const [depName, version] of Object.entries(
        this.assembly.dependencies,
      )) {
        const depInfo = this.assembly.dependencyClosure?.[depName];
        const depGem = depInfo?.targets?.ruby?.gem as string | undefined;
        if (depGem) {
          gemspecContent.push(
            `  s.add_runtime_dependency '${rubySq(depGem)}', ${toRubyVersionRange(version)}`,
          );
        }
      }
    }

    gemspecContent.push(`end`);

    await fs.writeFile(gemspecPath, gemspecContent.join('\n'), 'utf-8');
  }

  protected getAssemblyOutputDir(_mod: spec.Assembly) {
    return path.join('lib', path.dirname(_mod.name)).replace(/\\/g, '/');
  }

  protected onBeginInterface(_ifc: spec.InterfaceType) {} // eslint-disable-line @typescript-eslint/no-empty-function
  protected onEndInterface(_ifc: spec.InterfaceType) {} // eslint-disable-line @typescript-eslint/no-empty-function
  protected onInterfaceMethod(_ifc: spec.InterfaceType, _method: spec.Method) {} // eslint-disable-line @typescript-eslint/no-empty-function
  protected onInterfaceMethodOverload(
    _ifc: spec.InterfaceType,
    _overload: spec.Method,
    _originalMethod: spec.Method,
  ) {} // eslint-disable-line @typescript-eslint/no-empty-function
  protected onInterfaceProperty(
    _ifc: spec.InterfaceType,
    _prop: spec.Property,
  ) {} // eslint-disable-line @typescript-eslint/no-empty-function
  protected onProperty(_cls: spec.ClassType, _prop: spec.Property) {} // eslint-disable-line @typescript-eslint/no-empty-function
  protected onStaticProperty(_cls: spec.ClassType, _prop: spec.Property) {} // eslint-disable-line @typescript-eslint/no-empty-function
  protected onUnionProperty(
    _cls: spec.ClassType,
    _prop: spec.Property,
    _union: spec.UnionTypeReference,
  ) {} // eslint-disable-line @typescript-eslint/no-empty-function
  protected onMethod(_cls: spec.ClassType, _method: spec.Method) {} // eslint-disable-line @typescript-eslint/no-empty-function
  protected onMethodOverload(
    _cls: spec.ClassType,
    _overload: spec.Method,
    _originalMethod: spec.Method,
  ) {} // eslint-disable-line @typescript-eslint/no-empty-function
  protected onStaticMethod(_cls: spec.ClassType, _method: spec.Method) {} // eslint-disable-line @typescript-eslint/no-empty-function
  protected onStaticMethodOverload(
    _cls: spec.ClassType,
    _overload: spec.Method,
    _originalMethod: spec.Method,
  ) {} // eslint-disable-line @typescript-eslint/no-empty-function
}

export default RubyTarget;
