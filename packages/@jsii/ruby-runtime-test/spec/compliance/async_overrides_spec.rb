# frozen_string_literal: true

require 'spec_helper'

# Suite tests: asyncOverrides_*, voidReturningAsync.
#
# The OverrideAsyncMethodsByBaseClass, OverrideCallsSuper and TwoOverrides
# fixture classes are defined in spec/support/fixtures.rb.
RSpec.describe 'JSII compliance: async overrides' do
  it 'calls async methods synchronously from Ruby', compliance: 'asyncOverrides_callAsyncMethod' do
    obj = JsiiCalc::AsyncVirtualMethods.new
    expect(obj.call_me()).to eq(128)
    expect(obj.override_me(44)).to eq(528)
  end

  it 'invokes guest overrides of async methods', compliance: 'asyncOverrides_overrideAsyncMethod' do
    class MyOverride < JsiiCalc::AsyncVirtualMethods
      def override_me(mult)
        mult * 2
      end
    end
    obj = MyOverride.new
    expect(obj.call_me()).to eq(28)
  end

  it 'invokes async overrides inherited from a parent class', compliance: 'asyncOverrides_overrideAsyncMethodByParentClass' do
    # OverrideAsyncMethodsByBaseClass inherits override from parent
    obj = OverrideAsyncMethodsByBaseClass.new
    expect(obj.call_me).to eq(4452)
  end

  it 'lets async overrides call super', compliance: 'asyncOverrides_overrideCallsSuper' do
    obj = OverrideCallsSuper.new
    expect(obj.override_me(12)).to eq(1441)
    expect(obj.call_me).to eq(1209)
  end

  it 'supports two simultaneous async overrides', compliance: 'asyncOverrides_twoOverrides' do
    obj = TwoOverrides.new
    expect(obj.call_me).to eq(684)
  end

  it 'propagates exceptions raised in async overrides', compliance: 'asyncOverrides_overrideThrows' do
    klass = Class.new(JsiiCalc::AsyncVirtualMethods) do
      def override_me(mult)
        raise 'Thrown by native code'
      end
    end

    obj = klass.new
    expect { obj.call_me }.to raise_error(Jsii::RuntimeError, /Thrown by native code/)
  end

  it 'handles Promise<void>-returning async methods', compliance: 'voidReturningAsync' do
    expect(JsiiCalc::PromiseNothing.new.instance_promise_it).to be_nil
  end

  describe 'async overrides (extended)' do
    it 'can override async methods while keeping non-overridden ones intact' do
      class OverrideAsyncMethods < JsiiCalc::AsyncVirtualMethods
        def override_me(mult)
          mult * 2
        end

        def dont_override_me
          8
        end

        def override_me_too
          0
        end
      end

      obj = OverrideAsyncMethods.new
      expect(obj.call_me()).to eq(28)
      expect(obj.override_me(44)).to eq(88)
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
  end
end
