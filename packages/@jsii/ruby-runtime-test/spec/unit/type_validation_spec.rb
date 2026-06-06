require 'spec_helper'

RSpec.describe 'Runtime Type Validation' do
  it 'validates primitive types on property assignment' do
    types = JsiiCalc::AllTypes.new

    expect { types.string_property = 123 }.to raise_error(TypeError, /Expected stringProperty to be a String/)
    expect { types.number_property = "hello" }.to raise_error(TypeError, /Expected numberProperty to be a Numeric/)
    expect { types.boolean_property = "true" }.to raise_error(TypeError, /Expected booleanProperty to be a Boolean/)
  end

  it 'validates arrays and maps' do
    types = JsiiCalc::AllTypes.new

    expect { types.array_property = "not an array" }.to raise_error(TypeError, /Expected arrayProperty to be an Array/)
    expect { types.array_property = ["string", 123] }.to raise_error(TypeError, /Expected arrayProperty\[1\] to be a String/)

    expect { types.map_property = "not a hash" }.to raise_error(TypeError, /Expected mapProperty to be a Hash/)
    expect { types.map_property = { "foo" => "not a number" } }.to raise_error(TypeError, /Expected mapProperty\["foo"\] to be of type/)
  end

  it 'validates json property' do
    types = JsiiCalc::AllTypes.new

    expect { types.json_property = ["array", "of", "json"] }.not_to raise_error
    expect { types.json_property = { "foo" => "bar" } }.not_to raise_error
  end

  it 'does not allow hashes for class types' do
    expect { Jsii::Type.check_type({}, { 'fqn' => 'jsii-calc.Multiply' }, 'multiply_arg') }.to raise_error(TypeError, /Expected multiply_arg to be of type JsiiCalc::Multiply/)
  end

  describe 'union types' do
    let(:union_spec) do
      {
        'union' => {
          'types' => [
            { 'primitive' => 'string' },
            { 'primitive' => 'number' }
          ]
        }
      }
    end

    it 'accepts a value matching any arm' do
      expect { Jsii::Type.check_type('hello', union_spec, 'arg') }.not_to raise_error
      expect { Jsii::Type.check_type(42, union_spec, 'arg') }.not_to raise_error
    end

    it 'raises TypeError when no arm matches' do
      expect do
        Jsii::Type.check_type(true, union_spec, 'arg')
      end.to raise_error(TypeError, /Expected arg to match one of the union types/)
    end

    it 'raises TypeError when value is nil and union does not allow it' do
      # The union type validator does not have an "optional" flag of its own;
      # nil should fail every arm and surface as a union mismatch.
      expect do
        Jsii::Type.check_type(nil, union_spec, 'arg')
      end.to raise_error(TypeError, /Expected arg to match one of the union types/)
    end
  end

  describe 'unknown type references' do
    it 'raises TypeError on a bare {} type ref' do
      expect { Jsii::Type.check_type('x', {}, 'arg') }.to raise_error(TypeError, /Unknown type reference/)
    end

    it 'raises TypeError on an unknown primitive' do
      expect do
        Jsii::Type.check_type('x', { 'primitive' => 'bigint' }, 'arg')
      end.to raise_error(TypeError, /Unknown primitive type/)
    end
  end
end
