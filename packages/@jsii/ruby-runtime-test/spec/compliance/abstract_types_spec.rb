# frozen_string_literal: true

require 'spec_helper'

# Suite tests: abstractMembersAreCorrectlyHandled, returnAbstract,
# unmarshallIntoAbstractType.
RSpec.describe 'JSII compliance: abstract types' do
  it 'handles abstract properties and methods correctly', compliance: 'abstractMembersAreCorrectlyHandled' do
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

  it 'returns abstract classes and interfaces from the kernel', compliance: 'returnAbstract' do
    obj = JsiiCalc::AbstractClassReturner.new
    obj2 = obj.give_me_abstract

    expect(obj2.abstract_method('John')).to eq('Hello, John!!')
    expect(obj2.prop_from_interface).to eq('propFromInterfaceValue')
    expect(obj2.non_abstract_method).to eq(42)

    iface = obj.give_me_interface
    expect(iface.prop_from_interface).to eq('propFromInterfaceValue')

    expect(obj.return_abstract_from_property.abstract_property).to eq('hello-abstract-property')
  end

  it 'unmarshalls values into abstract types', compliance: 'unmarshallIntoAbstractType' do
    calc = JsiiCalc::Calculator.new
    calc.add(120)
    expect(calc.curr.value).to eq(120)
  end

  describe 'abstract types (extended)' do
    it 'can implement and override abstract classes' do
      class MyAbstractRunner < JsiiCalc::AbstractClass
        attr_accessor :abstract_property, :prop_from_interface

        def abstract_method(name)
          "Hello, #{name}!"
        end
      end

      runner = MyAbstractRunner.new
      runner.abstract_property = 'prop-val'
      expect(runner.abstract_property).to eq('prop-val')
      expect(runner.abstract_method('Ruby')).to eq('Hello, Ruby!')
    end

    it 'can override methods in a deep hierarchy' do
      class DeepOverride < JsiiCalc::AbstractClass
        attr_accessor :abstract_property, :prop_from_interface

        def abstract_method(name)
          "Deeply #{name}"
        end

        def non_abstract_method
          "Overridden non-abstract"
        end
      end

      obj = DeepOverride.new
      expect(obj.abstract_method('Nested')).to eq('Deeply Nested')
      expect(obj.non_abstract_method).to eq('Overridden non-abstract')
    end
  end
end
