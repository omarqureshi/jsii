require 'spec_helper'
require 'date'

# Helper classes are defined lazily inside before(:all) blocks below
# because the JsiiCalc constants aren't loaded until the suite before hook.

RSpec.describe 'JSII Compliance' do
  before(:all) do
    # Define helper classes here, after JsiiCalc is loaded by spec_helper

    Object.const_set(:OverrideAsyncMethodsByBaseClass, Class.new(JsiiCalc::AsyncVirtualMethods) do
      def override_me(mult)
        foo * 2
      end
      def foo
        2222
      end
    end) unless Object.const_defined?(:OverrideAsyncMethodsByBaseClass)

    Object.const_set(:OverrideCallsSuper, Class.new(JsiiCalc::AsyncVirtualMethods) do
      def override_me(mult)
        super_ret = super(mult)
        super_ret * 10 + 1
      end
    end) unless Object.const_defined?(:OverrideCallsSuper)

    Object.const_set(:TwoOverrides, Class.new(JsiiCalc::AsyncVirtualMethods) do
      def override_me(mult)
        666
      end
      def override_me_too
        10
      end
    end) unless Object.const_defined?(:TwoOverrides)

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
  end

  describe 'Dates' do
    it 'handles date in both strong-typed and any context' do
      types = JsiiCalc::AllTypes.new

      # strong type
      date = DateTime.new(1970, 1, 1, 0, 0, 0.123)
      types.date_property = date
      expect(types.date_property).to eq(date)

      # weak type (any_property)
      date2 = DateTime.new(1970, 1, 1, 0, 0, 0.999)
      types.any_property = date2
      expect(types.any_property).to eq(date2)
    end
  end
  describe 'Dynamic Types (any) — extended' do
    it 'handles any_map_property' do
      types = JsiiCalc::AllTypes.new
      map = { 'MapKey' => 'MapValue', 'Goo' => 19_289_812 }
      types.any_map_property = map
      expect(types.any_map_property['Goo']).to eq(19_289_812)
    end
  end
  describe 'Enums — scoped module' do
    it 'can use enum from scoped package' do
      obj = JsiiCalc::ReferenceEnumFromScopedPackage.new
      expect(obj.foo).to eq(Scope::JsiiCalcLib::EnumFromScopedModule::VALUE2)
      obj.foo = Scope::JsiiCalcLib::EnumFromScopedModule::VALUE1
      expect(obj.load_foo).to eq(Scope::JsiiCalcLib::EnumFromScopedModule::VALUE1)
      obj.save_foo(Scope::JsiiCalcLib::EnumFromScopedModule::VALUE2)
      expect(obj.foo).to eq(Scope::JsiiCalcLib::EnumFromScopedModule::VALUE2)
    end
  end
  describe 'JS Object Literals' do
    it 'can unmarshal JS object literal to native' do
      obj = JsiiCalc::JSObjectLiteralToNative.new
      obj2 = obj.return_literal
      expect(obj2.prop_a).to eq('Hello')
      expect(obj2.prop_b).to eq(102)
    end

    it 'fluent API works with derived classes' do
      obj = JsiiCalc::AllTypes.new
      obj.string_property = 'Hello'
      obj.number_property = 12
      expect(obj.string_property).to eq('Hello')
      expect(obj.number_property).to eq(12)
    end

    it 'can use JS object literal implementing interface' do
      obj = JsiiCalc::JSObjectLiteralForInterface.new
      friendly = obj.give_me_friendly
      gen = obj.give_me_friendly_generator

      expect(friendly.hello).to eq('I am literally friendly!')
      expect(gen.hello).to eq('giveMeFriendlyGenerator')
      expect(gen.next).to eq(42)
    end

    it 'can pass interface as method parameter' do
      obj = JsiiCalc::JSObjectLiteralForInterface.new
      friendly = obj.give_me_friendly
      augmenter = JsiiCalc::GreetingAugmenter.new

      expect(friendly.hello).to eq('I am literally friendly!')
      expect(augmenter.better_greeting(friendly)).to eq('I am literally friendly! Let me buy you a drink!')
    end
  end
  describe 'Structs — extended' do
    it 'accepts scalar second_level' do
      result = JsiiCalc::StructPassing.round_trip(123, required: 'hello', second_level: 5)
      expect(result.required).to eq('hello')
      expect(result.optional).to be_nil
      expect(result.second_level).to eq(5)
    end

    it 'handles structs in variadic args' do
      count = JsiiCalc::StructPassing.how_many_var_args_did_i_pass(
        123,
        JsiiCalc::TopLevelStruct.new(required: 'hello', second_level: 1),
        JsiiCalc::TopLevelStruct.new(required: 'bye', second_level: JsiiCalc::SecondLevelStruct.new(deeper_required_prop: 'ciao'))
      )
      expect(count).to eq(2)
    end

    it 'coerces plain hashes in variadic struct args' do
      # Generator emits `.map!` coercion for variadic struct params; this
      # exercises that path with raw hashes instead of explicit struct instances.
      count = JsiiCalc::StructPassing.how_many_var_args_did_i_pass(
        7,
        { required: 'one', second_level: 1 },
        { required: 'two', second_level: 2 }
      )
      expect(count).to eq(2)
    end

    it 'accepts a mix of struct instances and hashes for variadic args' do
      count = JsiiCalc::StructPassing.how_many_var_args_did_i_pass(
        0,
        JsiiCalc::TopLevelStruct.new(required: 'one', second_level: 1),
        { required: 'two', second_level: 2 }
      )
      expect(count).to eq(2)
    end

    it 'erases unset optional data values' do
      opts = JsiiCalc::EraseUndefinedHashValuesOptions.new(option1: 'option1')
      expect(JsiiCalc::EraseUndefinedHashValues.does_key_exist(opts, 'option1')).to be true
      expect(JsiiCalc::EraseUndefinedHashValues.does_key_exist(opts, 'option2')).to be false
    end

    it 'struct union disambiguation' do
      a0 = JsiiCalc::StructA.new(required_string: 'Present!', optional_string: 'Bazinga!')
      a1 = JsiiCalc::StructA.new(required_string: 'Present!', optional_number: 1337)
      b0 = JsiiCalc::StructB.new(required_string: 'Present!', optional_boolean: true)
      b1 = JsiiCalc::StructB.new(required_string: 'Present!', optional_struct_a: a1)

      expect(JsiiCalc::StructUnionConsumer.is_struct_a(a0)).to be true
      expect(JsiiCalc::StructUnionConsumer.is_struct_a(a1)).to be true
      expect(JsiiCalc::StructUnionConsumer.is_struct_a(b0)).to be false
      expect(JsiiCalc::StructUnionConsumer.is_struct_a(b1)).to be false

      expect(JsiiCalc::StructUnionConsumer.is_struct_b(a0)).to be false
      expect(JsiiCalc::StructUnionConsumer.is_struct_b(a1)).to be false
      expect(JsiiCalc::StructUnionConsumer.is_struct_b(b0)).to be true
      expect(JsiiCalc::StructUnionConsumer.is_struct_b(b1)).to be true
    end

    it 'can pass nested struct as plain hash (RootStructValidator)' do
      JsiiCalc::RootStructValidator.validate(string_prop: 'Pickle Rick!!!')
      JsiiCalc::RootStructValidator.validate(string_prop: 'Pickle Rick!!!', nested_struct: nil)
      JsiiCalc::RootStructValidator.validate(string_prop: 'Pickle Rick!!!', nested_struct: { number_prop: 1337 })
    end

    it 'can downcast struct to parent type (Demonstrate982)' do
      expect(JsiiCalc::Demonstrate982.take_this).not_to be_nil
      expect(JsiiCalc::Demonstrate982.take_this_too).not_to be_nil
    end

    it 'serializes structs undecorated to kernel (JsonFormatter)' do
      json = JsiiCalc::JsonFormatter.stringify(
        JsiiCalc::StructB.new(required_string: 'Bazinga!', optional_boolean: false)
      )
      parsed = JSON.parse(json)
      expect(parsed['requiredString']).to eq('Bazinga!')
      expect(parsed['optionalBoolean']).to eq(false)
    end
  end
  describe 'Struct equality' do
    it 'structEquality' do
      a = JsiiCalc::TopLevelStruct.new(
        required: 'bye',
        second_level: JsiiCalc::SecondLevelStruct.new(deeper_required_prop: 'ciao')
      )
      b = JsiiCalc::TopLevelStruct.new(required: 'hello', second_level: 1)
      c = JsiiCalc::TopLevelStruct.new(required: 'hello', second_level: 1)
      d = JsiiCalc::SecondLevelStruct.new(deeper_required_prop: 'exists')

      expect(a).not_to eq(b)
      expect(b).to eq(c)
      expect(a).not_to eq(5)
      expect(a).not_to eq(d)
    end
  end
  describe 'Null / Undefined semantics' do
    it 'treats null as undefined for optional args' do
      obj = JsiiCalc::NullShouldBeTreatedAsUndefined.new('hello', nil)
      obj.give_me_undefined(nil)
      obj.give_me_undefined_inside_an_object(
        this_should_be_undefined: nil,
        array_with_three_elements_and_undefined_as_second_argument: ['hello', nil, 'boom']
      )
      obj.change_me_to_undefined = nil
      obj.verify_property_is_undefined
    end

    it 'null is a valid optional list' do
      expect(JsiiCalc::DisappointingCollectionSource.MAYBE_LIST).to be_nil
    end

    it 'null is a valid optional map' do
      expect(JsiiCalc::DisappointingCollectionSource.MAYBE_MAP).to be_nil
    end
  end
end
