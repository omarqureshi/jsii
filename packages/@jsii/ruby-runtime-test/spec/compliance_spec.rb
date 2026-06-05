require 'spec_helper'
require 'date'

RSpec.describe 'JSII Compliance' do
  describe 'Primitive Types' do
    it 'handles boolean, string, number, date, and json' do
      types = JsiiCalc::AllTypes.new

      # boolean
      types.boolean_property = true
      expect(types.boolean_property).to be true

      # string
      types.string_property = 'foo'
      expect(types.string_property).to eq('foo')

      # number
      types.number_property = 1234
      expect(types.number_property).to eq(1234)

      # date
      date = DateTime.new(1970, 1, 1, 0, 0, 0.123)
      # JSII usually expects timestamps or ISO strings for dates
      types.date_property = date
      expect(types.date_property).to eq(date)

      # json
      types.json_property = { 'Foo' => { 'bar' => 123 } }
      expect(types.json_property['Foo']).to eq({ 'bar' => 123 })
    end
  end

  describe 'Collection Types' do
    it 'handles arrays and maps' do
      types = JsiiCalc::AllTypes.new

      # array
      types.array_property = ['Hello', 'World']
      expect(types.array_property[1]).to eq('World')

      # map
      map = { 'Foo' => Scope::JsiiCalcLib::Number.new(123) }
      types.map_property = map
      # The map returned should have the hydrated objects
      expect(types.map_property['Foo']).to be_a(Scope::JsiiCalcLib::Number)
      expect(types.map_property['Foo'].value).to eq(123)
    end
  end

  describe 'Dynamic Types (any)' do
    it 'handles various types assigned to any_property' do
      types = JsiiCalc::AllTypes.new

      # boolean
      types.any_property = false
      expect(types.any_property).to be false

      # string
      types.any_property = 'String'
      expect(types.any_property).to eq('String')

      # number
      types.any_property = 12
      expect(types.any_property).to eq(12)

      # json
      types.any_property = { 'Goo' => ['Hello', { 'World' => 123 }] }
      got = types.any_property['Goo']
      expect(got).not_to be_nil
      expect(got[1]['World']).to eq(123)

      # array
      types.any_property = ['Hello', 'World']
      expect(types.any_property[0]).to eq('Hello')
      expect(types.any_property[1]).to eq('World')

      # array of any
      types.any_array_property = ['Hybrid', Scope::JsiiCalcLib::Number.new(12), 123, false]
      expect(types.any_array_property[2]).to eq(123)
      expect(types.any_array_property[1]).to be_a(Scope::JsiiCalcLib::Number)

      # map
      map = { 'MapKey' => 'MapValue' }
      types.any_property = map
      expect(types.any_property['MapKey']).to eq('MapValue')

      # classes
      mult = JsiiCalc::Multiply.new(Scope::JsiiCalcLib::Number.new(10), Scope::JsiiCalcLib::Number.new(20))
      types.any_property = mult
      expect(types.any_property.jsii_ref).to eq(mult.jsii_ref)
      expect(types.any_property).to be_a(JsiiCalc::Multiply)
      expect(types.any_property.value).to eq(200)
    end
  end

  describe 'Union Types' do
    it 'handles union properties' do
      types = JsiiCalc::AllTypes.new

      # single valued property
      types.union_property = 1234
      expect(types.union_property).to eq(1234)

      types.union_property = 'Hello'
      expect(types.union_property).to eq('Hello')

      types.union_property = JsiiCalc::Multiply.new(Scope::JsiiCalcLib::Number.new(2), Scope::JsiiCalcLib::Number.new(12))
      expect(types.union_property.value).to eq(24)

      # array
      types.union_array_property = [123, Scope::JsiiCalcLib::Number.new(33)]
      expect(types.union_array_property[1].value).to eq(33)
    end
  end

  describe 'Calculator' do
    it 'can be created with constructor overloads' do
      JsiiCalc::Calculator.new
      JsiiCalc::Calculator.new(maximum_value: 10)
    end

    it 'can get and set primitive properties' do
      number = Scope::JsiiCalcLib::Number.new(20)
      expect(number.value).to eq(20)
      expect(number.double_value).to eq(40)

      expect(JsiiCalc::Negate.new(JsiiCalc::Add.new(Scope::JsiiCalcLib::Number.new(20), Scope::JsiiCalcLib::Number.new(10))).value).to eq(-30)
    end

    it 'can call methods' do
      calc = JsiiCalc::Calculator.new
      calc.add(10)
      expect(calc.value).to eq(10)

      calc.mul(2)
      expect(calc.value).to eq(20)

      calc.pow(5)
      expect(calc.value).to eq(20**5)

      calc.neg()
      expect(calc.value).to eq(-(20**5))
    end

    it 'can unmarshall into abstract types' do
      calc = JsiiCalc::Calculator.new
      calc.add(120)
      expect(calc.curr.value).to eq(120)
    end

    it 'can get and set non-primitive properties' do
      calc = JsiiCalc::Calculator.new
      calc.add(3_200_000)
      calc.neg()
      calc.curr = JsiiCalc::Multiply.new(Scope::JsiiCalcLib::Number.new(2), calc.curr)
      expect(calc.value).to eq(-6_400_000)
    end
  end

  describe 'Enums' do
    it 'can get and set enum values' do
      calc = JsiiCalc::Calculator.new
      calc.add(9)
      calc.pow(3)

      expect(calc.string_style).to eq(JsiiCalc::Composition::CompositeOperation::CompositionStringStyle::NORMAL)

      calc.string_style = JsiiCalc::Composition::CompositeOperation::CompositionStringStyle::DECORATED
      expect(calc.string_style).to eq(JsiiCalc::Composition::CompositeOperation::CompositionStringStyle::DECORATED)
      expect(calc.to_string()).to eq('<<[[{{(((1 * (0 + 9)) * (0 + 9)) * (0 + 9))}}]]>>')
    end
  end

  describe 'Structs' do
    it 'handles nested structs and property mapping' do
      struct = JsiiCalc::TopLevelStruct.new(
        required: 'hello',
        second_level: JsiiCalc::SecondLevelStruct.new(deeper_required_prop: 'exists')
      )
      
      result = JsiiCalc::StructPassing.round_trip(123, struct)
      expect(result).to be_a(JsiiCalc::TopLevelStruct)
      expect(result.required).to eq('hello')
      expect(result.second_level).to be_a(JsiiCalc::SecondLevelStruct)
      expect(result.second_level.deeper_required_prop).to eq('exists')
    end
  end

  describe 'Async Methods' do
    it 'can call async methods synchronously from Ruby' do
      obj = JsiiCalc::AsyncVirtualMethods.new
      expect(obj.call_me()).to eq(128)
      expect(obj.override_me(44)).to eq(528)
    end

    it 'can override async methods' do
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
  end

  describe 'Multiple Interfaces' do
    it 'can implement multiple JSII interfaces' do
      class MultiInterfaceResource < JsiiCalc::AllTypes
        include Scope::JsiiCalcLib::IFriendly
        include Scope::JsiiCalcLib::IDoublable

        attr_reader :double_value

        def initialize(value)
          super()
          @double_value = value * 2
        end

        def hello
          "I am multi-talented!"
        end
      end

      obj = MultiInterfaceResource.new(10)
      
      # Verify role 1: IFriendly
      poly = JsiiCalc::Polymorphism.new
      expect(poly.say_hello(obj)).to eq('oh, I am multi-talented!')

      # Verify role 2: IDoublable
      expect(obj).to be_a(Scope::JsiiCalcLib::IDoublable)
      expect(obj.double_value).to eq(20)
    end
  end
end
