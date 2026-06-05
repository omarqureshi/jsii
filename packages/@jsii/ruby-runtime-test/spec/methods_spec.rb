require 'spec_helper'
require 'date'
require 'json'

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

  describe 'Async Methods — extended' do
    it 'can override async methods via parent class' do
      # OverrideAsyncMethodsByBaseClass inherits override from parent
      obj = OverrideAsyncMethodsByBaseClass.new
      expect(obj.call_me).to eq(4452)
    end

    it 'can override async method calling super' do
      obj = OverrideCallsSuper.new
      expect(obj.override_me(12)).to eq(1441)
      expect(obj.call_me).to eq(1209)
    end

    it 'supports two simultaneous overrides' do
      obj = TwoOverrides.new
      expect(obj.call_me).to eq(684)
    end

    it 'propagates exception from async override' do
      klass = Class.new(JsiiCalc::AsyncVirtualMethods) do
        def override_me(mult)
          raise 'Thrown by native code'
        end
      end

      obj = klass.new
      expect { obj.call_me }.to raise_error(Jsii::RuntimeError, /Thrown by native code/)
    end

    it 'propagates ArgumentError from an async override (not just StandardError)' do
      klass = Class.new(JsiiCalc::AsyncVirtualMethods) do
        def override_me(mult)
          raise ArgumentError, 'argument blew up'
        end
      end

      expect { klass.new.call_me }.to raise_error(Jsii::RuntimeError, /argument blew up/)
    end

    it 'propagates TypeError from an async override' do
      klass = Class.new(JsiiCalc::AsyncVirtualMethods) do
        def override_me(mult)
          raise TypeError, 'wrong type'
        end
      end

      expect { klass.new.call_me }.to raise_error(Jsii::RuntimeError, /wrong type/)
    end

    it 'void-returning async returns nil' do
      expect(JsiiCalc::PromiseNothing.new.instance_promise_it).to be_nil
    end
  end
  describe 'Callbacks' do
    it 'correctly deserialize arguments' do
      klass = Class.new(JsiiCalc::DataRenderer) do
        def render_map(map)
          super(map)
        end
      end
      renderer = klass.new
      
      # The JS output uses 2 spaces indent and no trailing spaces, format is exactly:
      # {
      #   "anumber": 42,
      #   "astring": "bazinga!"
      # }
      result = renderer.render({ anumber: 42, astring: 'bazinga!' })
      # Compare structurally — the exact `JSON.stringify` formatting is a
      # Node-implementation detail and can change across Node versions.
      expect(JSON.parse(result)).to eq({ 'anumber' => 42, 'astring' => 'bazinga!' })
    end
  end
  describe 'Variadic methods' do
    it 'can invoke variadic methods' do
      variadic = JsiiCalc::VariadicMethod.new(1)
      expect(variadic.as_array(3, 4, 5, 6)).to eq([1, 3, 4, 5, 6])
    end
  end
  describe 'Fluent API' do
    it 'can be used with derived classes' do
      derived_from_all_types_class = Class.new(JsiiCalc::AllTypes)
      obj = derived_from_all_types_class.new
      obj.string_property = 'Hello'
      obj.number_property = 12
      
      expect(obj.string_property).to eq('Hello')
      expect(obj.number_property).to eq(12)
    end
  end
  describe 'Overloaded setter' do
    it 'can obtain reference with overloaded setter' do
      expect(JsiiCalc::ConfusingToJackson.make_instance).not_to be_nil
    end

    it 'can obtain struct reference with overloaded setter' do
      expect(JsiiCalc::ConfusingToJackson.make_struct_instance).not_to be_nil
    end
  end
end
