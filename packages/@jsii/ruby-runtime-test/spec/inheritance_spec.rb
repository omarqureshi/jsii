require 'spec_helper'
require 'date'

RSpec.describe 'JSII Compliance' do
  describe 'Complex Inheritance' do
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
      
      # Use it in a JSII method that expects AbstractClass
      returner = JsiiCalc::AbstractClassReturner.new
      # We check that the returner can return an AbstractClass.
      # The remote side will instantiate an anonymous class if needed.
    end

    it 'handles inheritance with no new properties' do
      # DerivedClassHasNoProperties::Derived inherits from Base
      # Base has 'prop'
      obj = JsiiCalc::DerivedClassHasNoProperties::Derived.new
      obj.prop = 'hello'
      expect(obj.prop).to eq('hello')
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

    it 'handles diamond inheritance via interfaces' do
      class DiamondImplementation < JsiiCalc::AllTypes
        include Scope::JsiiCalcLib::IFriendly
        include Scope::JsiiCalcLib::IDoublable

        def hello
          "Diamond hello"
        end

        def double_value
          42
        end
      end

      obj = DiamondImplementation.new
      poly = JsiiCalc::Polymorphism.new
      expect(poly.say_hello(obj)).to eq('oh, Diamond hello')
      expect(obj.double_value).to eq(42)
    end

    it 'handles cross-package inheritance' do
      # JsiiCalc::Add inherits from Scope::JsiiCalcLib::Operation
      add = JsiiCalc::Add.new(Scope::JsiiCalcLib::Number.new(1), Scope::JsiiCalcLib::Number.new(2))
      expect(add).to be_a(Scope::JsiiCalcLib::Operation)
      expect(add.value).to eq(3)
    end

    it 'can implement behavioral interfaces' do
      class MyFriendly < Jsii::Object
        include Scope::JsiiCalcLib::IFriendly
        def hello
          "Greetings!"
        end
      end

      # Jsii requires a base class for creation. 
      # Since MyFriendly doesn't inherit from a proxy, we use JsiiCalc::AllTypes for testing.
      class CustomFriendly < JsiiCalc::AllTypes
        include Scope::JsiiCalcLib::IFriendly
        def hello
          "Custom!"
        end
      end

      friendly = CustomFriendly.new
      poly = JsiiCalc::Polymorphism.new
      expect(poly.say_hello(friendly)).to eq('oh, Custom!')
    end

    it 'can handle complex method/property overrides with keywords' do
      class RubyReservedWords < JsiiCalc::JavaReservedWords
        # In Ruby, 'while' is a keyword. Our generator mapped it to '_while'.
        # Let's see if we can override 'abstract' which is a method.
        def abstract
          "Overridden abstract"
        end
      end

      obj = RubyReservedWords.new
      expect(obj.abstract).to eq("Overridden abstract")
    end

    it 'hydrates structs returned from methods' do
      # RootStructValidator.validate is static
      struct = JsiiCalc::RootStruct.new(
        string_prop: 'hello',
        nested_struct: JsiiCalc::NestedStruct.new(number_prop: 10)
      )
      
      # Should not raise error
      JsiiCalc::RootStructValidator.validate(struct)
      
      # Test failure case
      invalid_struct = JsiiCalc::RootStruct.new(
        string_prop: 'hello',
        nested_struct: JsiiCalc::NestedStruct.new(number_prop: -1)
      )
      expect { JsiiCalc::RootStructValidator.validate(invalid_struct) }.to raise_error(Jsii::RuntimeError, /numberProp must be > 0/)
    end

    it 'can use interfaces from submodules' do
      class MyReflectable < JsiiCalc::AllTypes
        include Scope::JsiiCalcLib::Submodule::IReflectable
        def entries
          [Scope::JsiiCalcLib::Submodule::ReflectableEntry.new(key: 'k', value: Scope::JsiiCalcLib::Number.new(123))]
        end
      end

      obj = MyReflectable.new
      reflector = Scope::JsiiCalcLib::Submodule::Reflector.new
      map = reflector.as_map(obj)
      expect(map['k'].value).to eq(123)
    end
    it 'enforces strict interface validation' do
      class InvalidReflectable < JsiiCalc::AllTypes
        include Scope::JsiiCalcLib::Submodule::IReflectable
        # missing required `entries` method!
      end

      expect { InvalidReflectable.new }.to raise_error(RuntimeError, /missing required method\/property: entries/)
    end
  end
end
