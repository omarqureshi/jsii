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

  describe 'Statics and Constants' do
    it 'supports static methods' do
      expect(JsiiCalc::Statics.static_method('Yoyo')).to eq('hello ,Yoyo!')
    end

    it 'supports static mutable instance' do
      expect(JsiiCalc::Statics.instance.value).to eq('default')

      new_statics = JsiiCalc::Statics.new('new value')
      JsiiCalc::Statics.instance = new_statics

      expect(JsiiCalc::Statics.instance.value).to eq('new value')
      expect(JsiiCalc::Statics.non_const_static).to eq(100)

      # reset back to default for other tests
      JsiiCalc::Statics.instance = JsiiCalc::Statics.new('default')
    end

    it 'supports constants' do
      # const properties take an UPPER_SNAKE_CASE form in Ruby (matches Python's
      # `toPythonPropertyName(name, constant=true)`) so they don't collide with
      # a sibling snake_case property of the same lowercased name.
      expect(JsiiCalc::Statics.FOO).to eq('hello')
      expect(JsiiCalc::Statics.CONST_OBJ.hello).to eq('world')
      expect(JsiiCalc::Statics.BAR).to eq(1234)
      expect(JsiiCalc::Statics.ZOO_BAR['hello']).to eq('world')
    end
  end
  describe 'Interfaces' do
    it 'supports full interface hierarchy (IFriendly, IFriendlier, IRandomNumberGenerator)' do
      add = JsiiCalc::Add.new(Scope::JsiiCalcLib::Number.new(10), Scope::JsiiCalcLib::Number.new(20))
      expect(add.hello).to eq("Hello, I am a binary operation. What's your name?")

      multiply = JsiiCalc::Multiply.new(Scope::JsiiCalcLib::Number.new(10), Scope::JsiiCalcLib::Number.new(30))
      expect(multiply.hello).to eq("Hello, I am a binary operation. What's your name?")
      expect(multiply.goodbye).to eq('Goodbye from Multiply!')
      expect(multiply.next).to eq(89)

      poly = JsiiCalc::Polymorphism.new
      expect(poly.say_hello(multiply)).to eq("oh, Hello, I am a binary operation. What's your name?")
    end

    it 'supports interface property setter' do
      obj = JsiiCalc::ObjectWithPropertyProvider.provide
      obj.property = 'New Value'
      expect(obj.was_set).to be true
    end

    it 'can receive instance of private class' do
      expect(JsiiCalc::ReturnsPrivateImplementationOfInterface.new.private_implementation.success).to be true
    end

    it 'supports ConsumerCanRingBell with native implementations' do
      bell_ringer_class = Class.new do
        include JsiiCalc::IBellRinger
        def your_turn(bell)
          bell.ring
        end
      end

      concrete_bell_ringer_class = Class.new do
        include JsiiCalc::IConcreteBellRinger
        def your_turn(bell)
          bell.ring
        end
      end

      bell_ringer = bell_ringer_class.new
      concrete_bell_ringer = concrete_bell_ringer_class.new

      expect(JsiiCalc::ConsumerCanRingBell.static_implemented_by_object_literal(bell_ringer)).to be true
      expect(JsiiCalc::ConsumerCanRingBell.static_implemented_by_public_class(bell_ringer)).to be true
      expect(JsiiCalc::ConsumerCanRingBell.static_implemented_by_private_class(bell_ringer)).to be true
      expect(JsiiCalc::ConsumerCanRingBell.static_when_typed_as_class(concrete_bell_ringer)).to be true

      consumer = JsiiCalc::ConsumerCanRingBell.new
      expect(consumer.implemented_by_object_literal(bell_ringer)).to be true
      expect(consumer.implemented_by_public_class(bell_ringer)).to be true
      expect(consumer.implemented_by_private_class(bell_ringer)).to be true
      expect(consumer.when_typed_as_class(concrete_bell_ringer)).to be true
    end

    it 'pure interfaces can be used transparently' do
      expected = JsiiCalc::StructB.new(required_string: "It's Britney b**ch!")

      delegate_class = Class.new do
        include JsiiCalc::IStructReturningDelegate
        def return_struct
          JsiiCalc::StructB.new(required_string: "It's Britney b**ch!")
        end
      end

      delegate = delegate_class.new
      consumer = JsiiCalc::ConsumePureInterface.new(delegate)
      result = consumer.work_it_baby
      expect(result.required_string).to eq(expected.required_string)
    end

    it 'supports anonymous implementation provider' do
      provider = JsiiCalc::AnonymousImplementationProvider.new
      expect(provider.provide_as_class.value).to eq(1337)
      expect(provider.provide_as_interface.value).to eq(1337)
      expect(provider.provide_as_interface.verb).to eq('to implement')
    end

    it 'InterfaceCollections list of structs' do
      JsiiCalc::InterfaceCollections.list_of_structs.each do |elt|
        expect(elt.required_string).not_to be_nil
      end
    end

    it 'InterfaceCollections list of interfaces' do
      JsiiCalc::InterfaceCollections.list_of_interfaces.each do |elt|
        expect(elt).to respond_to(:ring)
      end
    end

    it 'InterfaceCollections map of structs' do
      JsiiCalc::InterfaceCollections.map_of_structs.each_value do |elt|
        expect(elt.required_string).not_to be_nil
      end
    end

    it 'InterfaceCollections map of interfaces' do
      JsiiCalc::InterfaceCollections.map_of_interfaces.each_value do |elt|
        expect(elt).to respond_to(:ring)
      end
    end
  end
  describe 'Abstract suite' do
    it 'handles abstract property and method correctly' do
      klass = Class.new(JsiiCalc::AbstractSuite) do
        def initialize
          super
          @property_val = nil
        end

        def some_method(str)
          "Wrapped<#{str}>"
        end

        def property
          @property_val
        end

        def property=(value)
          @property_val = "String<#{value}>"
        end
      end

      abstract_suite = klass.new
      expect(abstract_suite.work_it_all('Oomf!')).to eq('Wrapped<String<Oomf!>>')
    end
  end
  describe 'Return abstract' do
    it 'AbstractClassReturner provides abstract values' do
      obj = JsiiCalc::AbstractClassReturner.new
      obj2 = obj.give_me_abstract

      expect(obj2.abstract_method('John')).to eq('Hello, John!!')
      expect(obj2.prop_from_interface).to eq('propFromInterfaceValue')
      expect(obj2.non_abstract_method).to eq(42)

      iface = obj.give_me_interface
      expect(iface.prop_from_interface).to eq('propFromInterfaceValue')

      expect(obj.return_abstract_from_property.abstract_property).to eq('hello-abstract-property')
    end
  end
  describe 'Private members' do
    it 'private methods are not overrideable' do
      klass = Class.new(JsiiCalc::DoNotOverridePrivates) do
        def private_method
          'privateMethod-Override'
        end
      end
      obj = klass.new
      expect(obj.private_method_value).to eq('privateMethod')
    end

    it 'private property by name is not overrideable' do
      klass = Class.new(JsiiCalc::DoNotOverridePrivates) do
        def private_property
          'privateProperty-Override'
        end
      end
      obj = klass.new
      expect(obj.private_property_value).to eq('privateProperty')
    end

    it 'private property getter/setter are not overrideable' do
      klass = Class.new(JsiiCalc::DoNotOverridePrivates) do
        def private_property
          'privateProperty-Override'
        end
        def private_property=(value)
          raise 'Boom'
        end
      end
      obj = klass.new
      expect(obj.private_property_value).to eq('privateProperty')

      # setter override is also not invoked
      obj.change_private_property_value('MyNewValue')
      expect(obj.private_property_value).to eq('MyNewValue')
    end

    it 'doNotOverridePrivates_property_by_name_public' do
      klass = Class.new(JsiiCalc::DoNotOverridePrivates) do
        def private_property
          'privateProperty-Override'
        end
      end
      obj = klass.new
      expect(obj.private_property_value).to eq('privateProperty')
    end

    it 'doNotOverridePrivates_property_getter_public' do
      klass = Class.new(JsiiCalc::DoNotOverridePrivates) do
        def private_property
          'privateProperty-Override'
        end
        def private_property=(value)
          raise 'Boom'
        end
      end
      obj = klass.new
      expect(obj.private_property_value).to eq('privateProperty')
      obj.change_private_property_value('MyNewValue')
      expect(obj.private_property_value).to eq('MyNewValue')
    end
  end
  describe 'Private constructors and auto properties' do
    it 'supports factory method pattern with auto properties' do
      obj = JsiiCalc::ClassWithPrivateConstructorAndAutomaticProperties.create('Hello', 'Bye')
      expect(obj.read_write_string).to eq('Bye')
      expect(obj.read_only_string).to eq('Hello')
    end
  end
  describe 'ClassWithSelf' do
    it 'handles parameters named self' do
      subject = JsiiCalc::PythonSelf::ClassWithSelf.new('Howdy!')
      expect(subject.self).to eq('Howdy!')
      expect(subject.method(1337)).to eq('1337')
    end

    it 'can extend and implement from jsii' do
      klass = Class.new(JsiiCalc::PythonSelf::ClassWithSelf) do
        include JsiiCalc::IWallClock
        def initialize(now)
          super(now)
          @now = now
        end
        def iso8601_now
          @now
        end
      end
      
      require 'time'
      mild_entropy_class = Class.new(JsiiCalc::Entropy) do
        def repeat(word)
          word
        end
      end
      
      now_str = Time.now.utc.iso8601
      wall_clock = klass.new(now_str)
      entropy = mild_entropy_class.new(wall_clock)
      expect(entropy.increase).to eq(now_str)
    end
  end
  describe 'Kwargs from superinterface' do
    it 'are working' do
      expect(JsiiCalc::Submodule::Isolated::Kwargs.method(extra: 'ordinary', prop: JsiiCalc::Submodule::Child::SomeEnum::SOME)).to be_truthy
    end
  end
  describe 'Lifted kwarg' do
    it 'with same name as positional arg' do
      bell = JsiiCalc::Bell.new
      amb = JsiiCalc::AmbiguousParameters.new(bell, scope: 'Driiiing!')
      
      expect(amb.scope).to eq(bell)
      # Assuming struct equality works
      expect(amb.props).to eq(JsiiCalc::StructParameterType.new(scope: 'Driiiing!'))
    end
  end
end
