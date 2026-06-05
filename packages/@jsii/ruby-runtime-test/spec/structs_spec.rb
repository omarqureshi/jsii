# frozen_string_literal: true

require 'spec_helper'
require 'date'

RSpec.describe 'JSII Structs Compliance' do
  it 'structs_nonOptionalhashCode' do
    struct_a = JsiiCalc::StableStruct.new(readonly_property: 'one')
    struct_b = JsiiCalc::StableStruct.new(readonly_property: 'one')
    struct_c = JsiiCalc::StableStruct.new(readonly_property: 'two')

    expect(struct_a.hash).to eq(struct_b.hash)
    expect(struct_a.hash).not_to eq(struct_c.hash)
  end

  it 'structs_optionalEquals' do
    struct_a = JsiiCalc::OptionalStruct.new(field: 'one')
    struct_b = JsiiCalc::OptionalStruct.new(field: 'one')
    struct_c = JsiiCalc::OptionalStruct.new(field: 'two')
    struct_d = JsiiCalc::OptionalStruct.new()

    expect(struct_a).to eq(struct_b)
    expect(struct_a).not_to eq(struct_c)
    expect(struct_a).not_to eq(struct_d)
  end

  it 'structs_optionalHashCode' do
    struct_a = JsiiCalc::OptionalStruct.new(field: 'one')
    struct_b = JsiiCalc::OptionalStruct.new(field: 'one')
    struct_c = JsiiCalc::OptionalStruct.new(field: 'two')
    struct_d = JsiiCalc::OptionalStruct.new()

    expect(struct_a.hash).to eq(struct_b.hash)
    expect(struct_a.hash).not_to eq(struct_c.hash)
    expect(struct_a.hash).not_to eq(struct_d.hash)
  end

  it 'structs_multiplePropertiesHashCode' do
    struct_a = JsiiCalc::DiamondInheritanceTopLevelStruct.new(
      base_level_property: 'one',
      first_mid_level_property: 'two',
      second_mid_level_property: 'three',
      top_level_property: 'four'
    )
    struct_b = JsiiCalc::DiamondInheritanceTopLevelStruct.new(
      base_level_property: 'one',
      first_mid_level_property: 'two',
      second_mid_level_property: 'three',
      top_level_property: 'four'
    )
    struct_c = JsiiCalc::DiamondInheritanceTopLevelStruct.new(
      base_level_property: 'one',
      first_mid_level_property: 'two',
      second_mid_level_property: 'different',
      top_level_property: 'four'
    )

    expect(struct_a.hash).to eq(struct_b.hash)
    expect(struct_a.hash).not_to eq(struct_c.hash)
  end

  it 'structs_containsNullChecks' do
    # In Ruby, missing required keyword arguments raise ArgumentError
    expect { Scope::JsiiCalcLib::MyFirstStruct.new }.to raise_error(ArgumentError)
  end

  it 'structs_serializeToJsii' do
    first_struct = Scope::JsiiCalcLib::MyFirstStruct.new(
      astring: 'FirstString',
      anumber: 999,
      first_optional: ['First', 'Optional']
    )

    double_trouble = JsiiCalc::DoubleTrouble.new()

    derived_struct = JsiiCalc::DerivedStruct.new(
      non_primitive: double_trouble,
      bool: false,
      another_required: DateTime.now,
      astring: 'String',
      anumber: 1234,
      first_optional: ['one', 'two']
    )

    gms = JsiiCalc::GiveMeStructs.new()
    expect(gms.read_first_number(first_struct)).to eq(999)
    expect(gms.read_first_number(derived_struct)).to eq(1234)
    expect(gms.read_derived_non_primitive(derived_struct).class).to eq(JsiiCalc::DoubleTrouble)

    literal = gms.struct_literal
    expect(literal.optional1).to eq('optional1FromStructLiteral')
    expect(literal.optional3).to be false
    expect(literal.optional2).to be_nil
  end

  it 'structs_stepBuilders' do
    # In Ruby, we use keyword arguments directly rather than generated step builders.
    some_instant = DateTime.now
    non_prim = JsiiCalc::DoubleTrouble.new()

    s = JsiiCalc::DerivedStruct.new(
      non_primitive: non_prim,
      bool: false,
      another_required: some_instant,
      astring: 'Hello',
      anumber: 1234,
      first_optional: ['Hello', 'World']
    )

    expect(s.non_primitive.class).to eq(JsiiCalc::DoubleTrouble)
    expect(s.bool).to be false
    expect(s.another_required.to_s).to eq(some_instant.to_s)
    expect(s.astring).to eq('Hello')
    expect(s.anumber).to eq(1234)
    expect(s.first_optional[1]).to eq('World')
    expect(s.another_optional).to be_nil
    expect(s.optional_array).to be_nil

    my_first_struct = Scope::JsiiCalcLib::MyFirstStruct.new(
      astring: 'Hello',
      anumber: 12
    )

    expect(my_first_struct.astring).to eq('Hello')
    expect(my_first_struct.anumber).to eq(12)

    only_options1 = Scope::JsiiCalcLib::StructWithOnlyOptionals.new(
      optional1: 'Hello',
      optional2: 1
    )

    expect(only_options1.optional1).to eq('Hello')
    expect(only_options1.optional2).to eq(1)
    expect(only_options1.optional3).to be_nil

    only_options2 = Scope::JsiiCalcLib::StructWithOnlyOptionals.new()
    expect(only_options2.optional1).to be_nil
    expect(only_options2.optional2).to be_nil
    expect(only_options2.optional3).to be_nil
  end

  it 'structs_withDiamondInheritance_correctlyDedupeProperties' do
    struct = JsiiCalc::DiamondInheritanceTopLevelStruct.new(
      base_level_property: 'base',
      first_mid_level_property: 'mid1',
      second_mid_level_property: 'mid2',
      top_level_property: 'top'
    )

    expect(struct.base_level_property).to eq('base')
    expect(struct.first_mid_level_property).to eq('mid1')
    expect(struct.second_mid_level_property).to eq('mid2')
    expect(struct.top_level_property).to eq('top')
  end

  it 'struct equality is symmetric' do
    child_class = Class.new(JsiiCalc::OptionalStruct)
    parent = JsiiCalc::OptionalStruct.new(field: 'one')
    child = child_class.new(field: 'one')

    expect(parent == child).to be false
    expect(child == parent).to be false
  end
end
