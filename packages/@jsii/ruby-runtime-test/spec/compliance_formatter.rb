require 'rspec/core/formatters/base_formatter'
require 'json'

class ComplianceFormatter < RSpec::Core::Formatters::BaseFormatter
  RSpec::Core::Formatters.register self, :example_passed, :example_failed, :close

  MAPPING = {
    # 1. compliance_part2_spec.rb
    "arrayReturnedByMethodCanBeRead" => "arrayReturnedByMethodCanBeRead",
    "asyncOverrides_overrideAsyncMethod" => "asyncOverrides_overrideAsyncMethod",
    "statics" => "statics",
    "structs_returnedLiteralEqualsNativeBuilt" => "structs_returnedLiteralEqualsNativeBuilt",
    "callbacksCorrectlyDeserializeArguments" => "callbacksCorrectlyDeserializeArguments",
    "propertyOverrides_interfaces" => "propertyOverrides_interfaces",
    "nullShouldBeTreatedAsUndefined" => "nullShouldBeTreatedAsUndefined",
    "reservedKeywordsAreSlugifiedInClassProperties" => "reservedKeywordsAreSlugifiedInClassProperties",
    "arrayReturnedByMethodCannotBeModified" => "arrayReturnedByMethodCannotBeModified",
    "mapReturnedByMethodCannotBeModified" => "mapReturnedByMethodCannotBeModified",
    "canLoadEnumValues" => "canLoadEnumValues",
    "canOverrideProtectedMethod" => "canOverrideProtectedMethod",
    "canOverrideProtectedGetter" => "canOverrideProtectedGetter",
    "canOverrideProtectedSetter" => "canOverrideProtectedSetter",
    "creationOfNativeObjectsFromJavaScriptObjects" => "creationOfNativeObjectsFromJavaScriptObjects",
    "downcasting" => "downcasting",
    "reservedKeywordsAreSlugifiedInMethodNames" => "reservedKeywordsAreSlugifiedInMethodNames",
    "reservedKeywordsAreSlugifiedInStructProperties" => "reservedKeywordsAreSlugifiedInStructProperties",
    "unionPropertiesWithBuilder" => "unionPropertiesWithBuilder",
    "fluentApi" => "fluentApi",
    "listInClassCanBeReadCorrectly" => "listInClassCanBeReadCorrectly",
    "mapInClassCannotBeModified" => "mapInClassCannotBeModified",
    "mapReturnedByMethodCanBeRead" => "mapReturnedByMethodCanBeRead",
    "staticListInClassCanBeReadCorrectly" => "staticListInClassCanBeReadCorrectly",
    "staticListInClassCannotBeModified" => "staticListInClassCannotBeModified",
    "staticMapInClassCanBeReadCorrectly" => "staticMapInClassCanBeReadCorrectly",
    "staticMapInClassCannotBeModified" => "staticMapInClassCannotBeModified",
    "testNativeObjectsWithInterfaces" => "testNativeObjectsWithInterfaces",
    "objRefsAreLabelledUsingWithTheMostCorrectType" => "objRefsAreLabelledUsingWithTheMostCorrectType",
    "equalsIsResistantToPropertyShadowingResultVariable" => "equalsIsResistantToPropertyShadowingResultVariable",
    "hashCodeIsResistantToPropertyShadowingResultVariable" => "hashCodeIsResistantToPropertyShadowingResultVariable",

    # 2. compliance_spec.rb
    "handles boolean, string, number, date, and json" => "primitiveTypes",
    "handles arrays and maps" => "collectionTypes",
    "handles various types assigned to any_property" => "dynamicTypes",
    "handles union properties" => "unionTypes",
    "can be created with constructor overloads" => "createObjectAndCtorOverloads",
    "can get and set primitive properties" => "getSetPrimitiveProperties",
    "can call methods" => "callMethods",
    "can unmarshall into abstract types" => "unmarshallIntoAbstractType",
    "can get and set non-primitive properties" => "getAndSetNonPrimitiveProperties",
    "can get and set enum values" => "getAndSetEnumValues",
    "handles nested structs and property mapping" => "useNestedStruct",
    "can call async methods synchronously from Ruby" => "asyncOverrides_callAsyncMethod",
    "can override async methods" => "doNotOverridePrivates_method_public",
    "can implement multiple JSII interfaces" => "interfacesCanBeUsedTransparently_WhenAddedToJsiiType",

    # 3. sync_overrides_spec.rb
    "can override sync virtual methods" => "syncOverrides",
    "can override sync property getter and setter" => "propertyOverrides_get_set",
    "can override property getter calling super" => "propertyOverrides_get_calls_super",
    "can override property setter calling super" => "propertyOverrides_set_calls_super",
    "raises from property getter override" => "propertyOverrides_get_throws",
    "raises from property setter override" => "propertyOverrides_set_throws",
    "can override property via interface" => "propertyOverrides_interfaces",
    "supports interface builder pattern" => "interfaceBuilder",
    "sync override can call super" => "syncOverrides_callsSuper",
    "raises when double-async is called in sync override (method)" => "fail_syncOverrides_callsDoubleAsync_method",
    "raises when double-async is called in sync override (property getter)" => "fail_syncOverrides_callsDoubleAsync_propertyGetter",
    "raises when double-async is called in sync override (property setter)" => "fail_syncOverrides_callsDoubleAsync_propertySetter",

    # 4. calculator_spec.rb
    "supports Sum parts (arrays)" => "arrays",
    "supports operations_map (maps)" => "maps",
    "supports union_property and read_union_value" => "unionProperties",
    "supports subclassing (AddTen)" => "subclassing",
    "raises when value exceeds max_value" => "exceptions",

    # 5. inheritance_spec.rb
    "can implement and override abstract classes" => "abstractMembersAreCorrectlyHandled",
    "isomorphism within constructor" => "classesCanSelfReferenceDuringClassInitialization",
    "supports factory method pattern with auto properties" => "classWithPrivateConstructorAndAutomaticProperties",
    "propagates exception from async override" => "asyncOverrides_overrideThrows",
    "supports two simultaneous overrides" => "asyncOverrides_twoOverrides",
    "private property getter/setter are not overrideable" => "doNotOverridePrivates_property_getter_private",
    "private property by name is not overrideable" => "doNotOverridePrivates_property_by_name_private",
    "private methods are not overrideable" => "doNotOverridePrivates_method_private",
    "doNotOverridePrivates_property_by_name_public" => "doNotOverridePrivates_property_by_name_public",
    "doNotOverridePrivates_property_getter_public" => "doNotOverridePrivates_property_getter_public",
    "InterfaceCollections map of structs" => "collectionOfInterfaces_MapOfStructs",
    "InterfaceCollections list of interfaces" => "collectionOfInterfaces_ListOfInterfaces",
    "InterfaceCollections map of interfaces" => "collectionOfInterfaces_MapOfInterfaces",
    "InterfaceCollections list of structs" => "collectionOfInterfaces_ListOfStructs",
    "pure interfaces can be used transparently" => "pureInterfacesCanBeUsedTransparently_WhenTransitivelyImplementing",
    "can implement behavioral interfaces" => "pureInterfacesCanBeUsedTransparently",
    "can pass interface as method parameter" => "testInterfaceParameter",
    "with same name as positional arg" => "liftedKwargWithSameNameAsPositionalArg",
    "erases unset optional data values" => "eraseUnsetDataValues",
    "AbstractClassReturner provides abstract values" => "returnAbstract",

    # 6. types_spec.rb
    "null is a valid optional map" => "testNullIsAValidOptionalMap",
    "null is a valid optional list" => "testNullIsAValidOptionalList",
    "handles any_map_property" => "mapInClassCanBeReadCorrectly",
    "can unmarshal JS object literal to native" => "testJSObjectLiteralToNative",
    "fluent API works with derived classes" => "testFluentApiWithDerivedClasses",
    "can use JS object literal implementing interface" => "testLiteralInterface",
    "handles date in both strong-typed and any context" => "dates",
    "struct union disambiguation" => "structs_nonOptionalequals",
    "can use enum from scoped package" => "useEnumFromScopedModule",

    # 7. regression_spec.rb
    "return_subclass_that_implements_interface (jsii#976)" => "returnSubclassThatImplementsInterface976",

    # 8. methods_spec.rb
    "can override async methods via parent class" => "asyncOverrides_overrideAsyncMethodByParentClass",
    "void-returning async returns nil" => "voidReturningAsync",
    "does not reallocate object id when constructor passes this out" => "objectIdDoesNotGetReallocatedWhenTheConstructorPassesThisOut",
    "can override async method calling super" => "asyncOverrides_overrideCallsSuper",
    "correctly deserialize arguments" => "correctlyDeserializesStructUnions",
    "can use interfaces from submodules" => "canUseInterfaceSetters",
    "can invoke variadic methods" => "variadicMethodCanBeInvoked",
    "can obtain reference with overloaded setter" => "canObtainReferenceWithOverloadedSetter",
    "can obtain struct reference with overloaded setter" => "canObtainStructReferenceWithOverloadedSetter",

    # 9. modules_spec.rb
    "can be received" => "strippedDeprecatedMemberCanBeReceived",
    "are usable" => "undefinedAndNull",
    "can be used when not expressly loaded" => "classCanBeUsedWhenNotExpressedlyLoaded",

    # 10. runtime_behavior_spec.rb
    "reports Ruby language and version" => "testJsiiAgent",
    "exposes fs, os, and crypto" => "nodeStandardLibrary",
    "ISO8601 strings are NOT auto-deserialized as dates" => "iso8601DoesNotDeserializeToDate",
    "propagates error message from JS" => "exceptionMessage",

    # 11. Additional discovered mappings
    "supports constants" => "consts",
    "supports anonymous implementation provider" => "canLeverageIndirectInterfacePolymorphism",
    "can receive instance of private class" => "receiveInstanceOfPrivateClass",
    "supports full interface hierarchy (IFriendly, IFriendlier, IRandomNumberGenerator)" => "testInterfaces",
    "serializes structs undecorated to kernel (JsonFormatter)" => "structsAreUndecoratedOntheWayToKernel",
    "can downcast struct to parent type (Demonstrate982)" => "testStructsCanBeDowncastedToParentType",
    "structEquality" => "structs_multiplePropertiesEquals",
    "structs_nonOptionalhashCode" => "structs_nonOptionalhashCode",
    "structs_optionalEquals" => "structs_optionalEquals",
    "structs_optionalHashCode" => "structs_optionalHashCode",
    "structs_multiplePropertiesHashCode" => "structs_multiplePropertiesHashCode",
    "structs_containsNullChecks" => "structs_containsNullChecks",
    "structs_serializeToJsii" => "structs_serializeToJsii",
    "structs_stepBuilders" => "structs_stepBuilders",
    "structs_withDiamondInheritance_correctlyDedupeProperties" => "structs_withDiamondInheritance_correctlyDedupeProperties",
    "supports ConsumerCanRingBell with native implementations" => "callbackParameterIsInterface",
  }

  def initialize(output)
    super(output)
    @results = {}
  end

  def example_passed(notification)
    map_example(notification.example, "success")
  end

  def example_failed(notification)
    map_example(notification.example, "failure")
  end

  def map_example(example, status)
    if MAPPING.key?(example.description)
      key = MAPPING[example.description]
      @results[key] = { status: status }
    end
  end

  def close(notification)
    File.write('compliance-report.json', JSON.pretty_generate(@results))
  end
end
