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

  describe 'Dependency Submodule Types' do
    it 'are usable' do
      subject = JsiiCalc::UpcasingReflectable.new('foo' => 'bar')
      expect(JsiiCalc::UpcasingReflectable.REFLECTOR.as_map(subject)).to eq('FOO' => 'bar')
    end
  end
  describe 'Submodule classes' do
    it 'can be used when not expressly loaded' do
      klass = Class.new(JsiiCalc::Cdk16625::Cdk16625) do
        def unwrap(gen)
          gen.next
        end
      end
      # This should NOT throw
      expect { klass.new.test }.not_to raise_error
    end
  end
  describe 'Stripped deprecated member' do
    it 'can be received' do
      expect(Scope::JsiiCalcLib::DeprecationRemoval::InterfaceFactory.create).not_to be_nil
    end
  end
end
