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

  describe 'Calculator — extended' do
    it 'supports Power operations' do
      expect(JsiiCalc::Power.new(Scope::JsiiCalcLib::Number.new(3), Scope::JsiiCalcLib::Number.new(4)).value).to eq(3**4)
      expect(JsiiCalc::Power.new(Scope::JsiiCalcLib::Number.new(999), Scope::JsiiCalcLib::Number.new(1)).value).to eq(999)
      expect(JsiiCalc::Power.new(Scope::JsiiCalcLib::Number.new(999), Scope::JsiiCalcLib::Number.new(0)).value).to eq(1)
    end

    it 'supports Multiply' do
      expect(JsiiCalc::Multiply.new(
        JsiiCalc::Add.new(Scope::JsiiCalcLib::Number.new(5), Scope::JsiiCalcLib::Number.new(5)),
        Scope::JsiiCalcLib::Number.new(2)
      ).value).to eq(20)
    end

    it 'handles nil max_value (undefined)' do
      calc = JsiiCalc::Calculator.new
      expect(calc.max_value).to be_nil
      calc.max_value = nil
    end

    it 'raises when value exceeds max_value' do
      calc = JsiiCalc::Calculator.new(initial_value: 20, maximum_value: 30)
      calc.add(3)
      expect(calc.value).to eq(23)

      expect { calc.add(10) }.to raise_error(Jsii::RuntimeError)

      calc.max_value = 40
      calc.add(10)
      expect(calc.value).to eq(33)
    end

    it 'supports Sum parts (arrays)' do
      sum = JsiiCalc::Sum.new
      sum.parts = [
        Scope::JsiiCalcLib::Number.new(5),
        Scope::JsiiCalcLib::Number.new(10),
        JsiiCalc::Multiply.new(Scope::JsiiCalcLib::Number.new(2), Scope::JsiiCalcLib::Number.new(3))
      ]

      expect(sum.value).to eq(5 + 10 + (2 * 3))
      expect(sum.parts[0].value).to eq(5)
      expect(sum.parts[2].value).to eq(6)
      expect(sum.to_string).to eq('(((0 + 5) + 10) + (2 * 3))')
    end

    it 'supports operations_map (maps)' do
      calc = JsiiCalc::Calculator.new
      calc.add(10)
      calc.add(20)
      calc.mul(2)

      expect(calc.operations_map['add'].length).to eq(2)
      expect(calc.operations_map['mul'].length).to eq(1)
      expect(calc.operations_map['add'][1].value).to eq(30)
    end

    it 'supports union_property and read_union_value' do
      calc = JsiiCalc::Calculator.new
      calc.union_property = JsiiCalc::Multiply.new(Scope::JsiiCalcLib::Number.new(9), Scope::JsiiCalcLib::Number.new(3))
      expect(calc.union_property).to be_a(JsiiCalc::Multiply)
      expect(calc.read_union_value).to eq(9 * 3)

      calc.union_property = JsiiCalc::Power.new(Scope::JsiiCalcLib::Number.new(10), Scope::JsiiCalcLib::Number.new(3))
      expect(calc.union_property).to be_a(JsiiCalc::Power)
      expect(calc.read_union_value).to eq(10**3)
    end

    it 'supports subclassing (AddTen)' do
      calc = JsiiCalc::Calculator.new
      calc.curr = AddTen.new(33)
      calc.neg
      expect(calc.value).to eq(-43)
    end
  end
end
