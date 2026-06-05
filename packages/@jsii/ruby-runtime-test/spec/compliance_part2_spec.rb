require 'spec_helper'

RSpec.describe 'JSII Compliance Part 2' do
  before(:all) do
    Object.const_set(:AddTen, Class.new(JsiiCalc::Add) do
      def initialize(value)
        super(Scope::JsiiCalcLib::Number.new(value), Scope::JsiiCalcLib::Number.new(10))
      end
    end) unless Object.const_defined?(:AddTen)

    Object.const_set(:MulTen, Class.new(JsiiCalc::Multiply) do
      def initialize(value)
        super(Scope::JsiiCalcLib::Number.new(value), Scope::JsiiCalcLib::Number.new(10))
      end
    end) unless Object.const_defined?(:MulTen)

    Object.const_set(:PureNativeFriendlyRandom, Class.new do
      include JsiiCalc::IFriendlyRandomGenerator

      def initialize
        @next_number = 1000
      end

      def _next
        n = @next_number
        @next_number += 1000
        n
      end

      def hello
        "I am a native!"
      end
    end) unless Object.const_defined?(:PureNativeFriendlyRandom)

    Object.const_set(:SubclassNativeFriendlyRandom, Class.new(Scope::JsiiCalcLib::Number) do
      include Scope::JsiiCalcLib::IFriendly
      include JsiiCalc::IRandomNumberGenerator

      def initialize
        super(908)
        @next_number = 100
      end

      def hello
        "SubclassNativeFriendlyRandom"
      end

      def _next
        n = @next_number
        @next_number += 100
        n
      end
    end) unless Object.const_defined?(:SubclassNativeFriendlyRandom)
  end

  it 'arrayReturnedByMethodCanBeRead' do
    list = JsiiCalc::ClassWithCollections.create_a_list()
    expect(list).to eq(['one', 'two'])
  end

  it 'asyncOverrides_overrideAsyncMethod' do
    class MyOverride < JsiiCalc::AsyncVirtualMethods
      def override_me(mult)
        mult * 2
      end
    end
    obj = MyOverride.new
    expect(obj.call_me()).to eq(28)
  end

  it 'statics' do
    expect(JsiiCalc::Statics.static_method('Yoyo')).to eq('hello ,Yoyo!')
    expect(JsiiCalc::Statics.instance.value).to eq('default')
    new_statics = JsiiCalc::Statics.new('new value')
    JsiiCalc::Statics.instance = new_statics
    expect(JsiiCalc::Statics.instance.value).to eq('new value')
    expect(JsiiCalc::Statics.non_const_static).to eq(100)
  end

  it 'structs_returnedLiteralEqualsNativeBuilt' do
    gms = JsiiCalc::GiveMeStructs.new
    returned_literal = gms.struct_literal
    native_built = Scope::JsiiCalcLib::StructWithOnlyOptionals.new(
      optional1: "optional1FromStructLiteral",
      optional3: false
    )
    expect(returned_literal.optional1).to eq(native_built.optional1)
    expect(returned_literal.optional2).to eq(native_built.optional2)
    expect(returned_literal.optional3).to eq(native_built.optional3)
  end

  it 'callbacksCorrectlyDeserializeArguments' do
    class MyRenderer < JsiiCalc::DataRenderer
      def render_map(map)
        super(map)
      end
    end
    renderer = MyRenderer.new
    expect(renderer.render).to eq("{\n  \"anumber\": 42,\n  \"astring\": \"bazinga!\"\n}")
  end

  it 'propertyOverrides_interfaces' do
    class MyInterfaceObj
      include JsiiCalc::IInterfaceWithProperties
      attr_reader :read_only_string

      def initialize
        @x = nil
        @read_only_string = "READ_ONLY_STRING"
      end

      def read_write_string
        "#{@x}?"
      end

      def read_write_string=(val)
        @x = "#{val}!"
      end
    end

    obj = MyInterfaceObj.new
    interact = JsiiCalc::UsesInterfaceWithProperties.new(obj)
    expect(interact.just_read).to eq("READ_ONLY_STRING")

    expect(interact.write_and_read("Hello")).to eq("Hello!?")
  end

  it 'nullShouldBeTreatedAsUndefined' do
    obj = JsiiCalc::NullShouldBeTreatedAsUndefined.new("hello", nil)
    obj.give_me_undefined(nil)
    obj.give_me_undefined_inside_an_object(
      JsiiCalc::NullShouldBeTreatedAsUndefinedData.new(
        this_should_be_undefined: nil,
        array_with_three_elements_and_undefined_as_second_argument: ["hello", nil, "boom"]
      )
    )
    obj.change_me_to_undefined = nil
    obj.verify_property_is_undefined()
  end

  it 'reservedKeywordsAreSlugifiedInClassProperties' do
    obj = JsiiCalc::ClassWithJavaReservedWords.new("one")
    expect(obj.int).to eq("one")
    expect(obj.import("two")).to eq("onetwo")
  end

  it 'arrayReturnedByMethodCannotBeModified' do
    list = JsiiCalc::ClassWithCollections.create_a_list()
    expect(list).to be_frozen
    expect { list << 'three' }.to raise_error(FrozenError)
  end

  it 'mapReturnedByMethodCannotBeModified' do
    map = JsiiCalc::ClassWithCollections.create_a_map()
    expect(map).to be_frozen
    expect { map['keyThree'] = 'valueThree' }.to raise_error(FrozenError)
  end

  it 'canLoadEnumValues' do
    expect(JsiiCalc::EnumDispenser.random_string_like_enum()).not_to be_nil
    expect(JsiiCalc::EnumDispenser.random_integer_like_enum()).not_to be_nil
  end

  it 'canOverrideProtectedMethod' do
    klass = Class.new(JsiiCalc::OverridableProtectedMember) do
      def override_me
        "Cthulhu Fhtagn!"
      end
    end

    overridden = klass.new
    expect(overridden.value_from_protected()).to eq("Cthulhu Fhtagn!")
  end

  it 'canOverrideProtectedGetter' do
    klass = Class.new(JsiiCalc::OverridableProtectedMember) do
      def override_read_only
        "Cthulhu "
      end

      def override_read_write
        "Fhtagn!"
      end
    end

    overridden = klass.new
    expect(overridden.value_from_protected()).to eq("Cthulhu Fhtagn!")
  end

  it 'canOverrideProtectedSetter' do
    klass = Class.new(JsiiCalc::OverridableProtectedMember) do
      def override_read_write
        super
      end

      def override_read_write=(value)
        super("zzzzzzzzz#{value}")
      end
    end

    overridden = klass.new
    overridden.switch_modes()
    expect(overridden.value_from_protected()).to eq("Bazzzzzzzzzzzaar...")
  end

  it 'creationOfNativeObjectsFromJavaScriptObjects' do
    types = JsiiCalc::AllTypes.new

    js_obj = Scope::JsiiCalcLib::Number.new(44)
    types.any_property = js_obj
    unmarshalled_js_obj = types.any_property
    expect(unmarshalled_js_obj.class).to eq(Scope::JsiiCalcLib::Number)

    native_obj = AddTen.new(10)
    types.any_property = native_obj
    result1 = types.any_property
    expect(result1).to be(native_obj)

    native_obj2 = MulTen.new(20)
    types.any_property = native_obj2
    unmarshalled_native_obj = types.any_property
    expect(unmarshalled_native_obj.class).to eq(MulTen)
    expect(unmarshalled_native_obj).to be(native_obj2)
  end

  it 'downcasting' do
    any_value = JsiiCalc::SomeTypeJsii976.return_anonymous
    real_value = Jsii.downcast(any_value, JsiiCalc::IReturnJsii976)
    expect(real_value.foo).to eq(1337)
  end

  it 'reservedKeywordsAreSlugifiedInMethodNames' do
    obj = JsiiCalc::PythonReservedWords.new
    obj.import
    obj._return
  end

  it 'reservedKeywordsAreSlugifiedInStructProperties' do
    struct = JsiiCalc::StructWithJavaReservedWords.new(
      assert: 'one',
      default: 'two'
    )
    expect(struct.assert).to eq('one')
    expect(struct.default).to eq('two')
  end

  it 'unionPropertiesWithBuilder' do
    obj1 = JsiiCalc::UnionProperties.new(bar: 12, foo: 'Hello')
    expect(obj1.bar).to eq(12)
    expect(obj1.foo).to eq('Hello')

    obj2 = JsiiCalc::UnionProperties.new(bar: 'BarIsString')
    expect(obj2.bar).to eq('BarIsString')
    expect(obj2.foo).to be_nil

    all_types = JsiiCalc::AllTypes.new
    obj3 = JsiiCalc::UnionProperties.new(bar: all_types, foo: 999)
    expect(obj3.bar).to eq(all_types)
    expect(obj3.foo).to eq(999)
  end

  it 'fluentApi' do
    calc3 = JsiiCalc::Calculator.new(initial_value: 20, maximum_value: 30)
    calc3.add(3)
    expect(calc3.value).to eq(23)
  end

  it 'listInClassCanBeReadCorrectly' do
    obj = JsiiCalc::ClassWithCollections.new({}, ['one', 'two'])
    expect(obj.array).to eq(['one', 'two'])
  end

  it 'mapInClassCannotBeModified' do
    obj = JsiiCalc::ClassWithCollections.new({ 'key' => 'value' }, [])
    expect(obj.map).to be_frozen
    expect { obj.map['keyTwo'] = 'valueTwo' }.to raise_error(FrozenError)
  end

  it 'mapReturnedByMethodCanBeRead' do
    map = JsiiCalc::ClassWithCollections.create_a_map()
    expect(map).to eq({ 'key1' => 'value1', 'key2' => 'value2' })
  end

  it 'staticListInClassCanBeReadCorrectly' do
    expect(JsiiCalc::ClassWithCollections.static_array).to eq(['one', 'two'])
  end

  it 'staticListInClassCannotBeModified' do
    list = JsiiCalc::ClassWithCollections.static_array
    expect(list).to be_frozen
    expect { list << 'three' }.to raise_error(FrozenError)
  end

  it 'staticMapInClassCanBeReadCorrectly' do
    map = JsiiCalc::ClassWithCollections.static_map
    expect(map).to eq({ 'key1' => 'value1', 'key2' => 'value2' })
  end

  it 'staticMapInClassCannotBeModified' do
    map = JsiiCalc::ClassWithCollections.static_map
    expect(map).to be_frozen
    expect { map['keyTwo'] = 'valueTwo' }.to raise_error(FrozenError)
  end

  it 'testNativeObjectsWithInterfaces' do
    pure_native = PureNativeFriendlyRandom.new
    subclassed_native = SubclassNativeFriendlyRandom.new

    generator_bound_to_subclassed_object = JsiiCalc::NumberGenerator.new(subclassed_native)
    expect(generator_bound_to_subclassed_object.generator).to be(subclassed_native)
    generator_bound_to_subclassed_object.is_same_generator(subclassed_native)
    expect(generator_bound_to_subclassed_object.next_times100()).to eq(10000)
    expect(generator_bound_to_subclassed_object.next_times100()).to eq(20000)

    generator_bound_to_pure_native = JsiiCalc::NumberGenerator.new(pure_native)
    expect(generator_bound_to_pure_native.generator).to be(pure_native)
    generator_bound_to_pure_native.is_same_generator(pure_native)
    expect(generator_bound_to_pure_native.next_times100()).to eq(100000)
    expect(generator_bound_to_pure_native.next_times100()).to eq(200000)
  end

  it 'objRefsAreLabelledUsingWithTheMostCorrectType' do
    class_ref = JsiiCalc::Constructors.make_class()
    iface_ref = JsiiCalc::Constructors.make_interface()

    expect(class_ref).to be_a(JsiiCalc::InbetweenClass)
    expect(iface_ref).not_to be_nil
  end

  it 'equalsIsResistantToPropertyShadowingResultVariable' do
    first = JsiiCalc::StructWithJavaReservedWords.new(default: 'one')
    second = JsiiCalc::StructWithJavaReservedWords.new(default: 'one')
    third = JsiiCalc::StructWithJavaReservedWords.new(default: 'two')

    expect(first).to eq(second)
    expect(first).not_to eq(third)
  end

  it 'hashCodeIsResistantToPropertyShadowingResultVariable' do
    first = JsiiCalc::StructWithJavaReservedWords.new(default: 'one')
    second = JsiiCalc::StructWithJavaReservedWords.new(default: 'one')
    third = JsiiCalc::StructWithJavaReservedWords.new(default: 'two')

    expect(first.hash).to eq(second.hash)
    expect(first.hash).not_to eq(third.hash)
  end
end
