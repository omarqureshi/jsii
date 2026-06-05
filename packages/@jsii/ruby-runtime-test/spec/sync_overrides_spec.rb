require 'spec_helper'

RSpec.describe 'JSII Compliance' do
  before(:all) do
    Object.const_set(:SyncOverrides, Class.new(JsiiCalc::SyncVirtualMethods) do
      attr_accessor :multiplier, :return_super, :call_async, :another_the_property

      def initialize
        super
        @multiplier = 1
        @return_super = false
        @call_async = false
        @another_the_property = nil
      end

      def virtual_method(n)
        return super(n) if @return_super

        if @call_async
          obj = JsiiCalc::AsyncVirtualMethods.new
          return obj.call_me
        end

        5 * n * @multiplier
      end

      def the_property
        'I am an override!'
      end

      def the_property=(value)
        @another_the_property = value
      end
    end) unless Object.const_defined?(:SyncOverrides)
  end

  describe 'Sync Virtual Methods' do
    it 'can override sync virtual methods' do
      obj = SyncOverrides.new
      expect(obj.caller_is_method).to eq(10 * 5)

      obj.multiplier = 5
      expect(obj.caller_is_method).to eq(10 * 5 * 5)

      # verify callbacks are invoked from a property
      expect(obj.caller_is_property).to eq(10 * 5 * 5)

      # and from an async method
      obj.multiplier = 3
      expect(obj.caller_is_async).to eq(10 * 5 * 3)
    end

    it 'can override sync property getter and setter' do
      so = SyncOverrides.new
      expect(so.retrieve_value_of_the_property).to eq('I am an override!')
      so.modify_value_of_the_property('New Value')
      expect(so.another_the_property).to eq('New Value')
    end

    it 'can override property getter calling super' do
      klass = Class.new(JsiiCalc::SyncVirtualMethods) do
        def the_property
          "super:#{super}"
        end

        def the_property=(value)
          super(value)
        end
      end

      so = klass.new
      expect(so.retrieve_value_of_the_property).to eq('super:initial value')
      expect(so.the_property).to eq('super:initial value')
    end

    it 'can override property setter calling super' do
      klass = Class.new(JsiiCalc::SyncVirtualMethods) do
        def the_property
          super
        end

        def the_property=(value)
          super("#{value}:by override")
        end
      end

      so = klass.new
      so.modify_value_of_the_property('New Value')
      expect(so.the_property).to eq('New Value:by override')
    end

    it 'raises from property getter override' do
      klass = Class.new(JsiiCalc::SyncVirtualMethods) do
        def the_property
          raise 'Oh no, this is bad'
        end

        def the_property=(value)
          super(value)
        end
      end

      so = klass.new
      expect { so.retrieve_value_of_the_property }.to raise_error(Jsii::RuntimeError, /Oh no, this is bad/)
    end

    it 'raises from property setter override' do
      klass = Class.new(JsiiCalc::SyncVirtualMethods) do
        def the_property
          super
        end

        def the_property=(value)
          raise 'Exception from overloaded setter'
        end
      end

      so = klass.new
      expect { so.modify_value_of_the_property('Hii') }.to raise_error(Jsii::RuntimeError, /Exception from overloaded setter/)
    end

    it 'can override property via interface' do
      klass = Class.new do
        include JsiiCalc::IInterfaceWithProperties

        attr_reader :read_only_string

        def initialize
          @x = nil
          @read_only_string = 'READ_ONLY_STRING'
        end

        def read_write_string
          "#{@x}?"
        end

        def read_write_string=(value)
          @x = "#{value}!"
        end
      end

      obj = klass.new
      interact = JsiiCalc::UsesInterfaceWithProperties.new(obj)
      expect(interact.just_read).to eq('READ_ONLY_STRING')
      expect(interact.write_and_read('Hello')).to eq('Hello!?')
    end

    it 'supports interface builder pattern' do
      klass = Class.new do
        include JsiiCalc::IInterfaceWithProperties

        attr_reader :read_only_string

        def initialize
          @x = 'READ_WRITE'
          @read_only_string = 'READ_ONLY'
        end

        def read_write_string
          @x
        end

        def read_write_string=(value)
          @x = value
        end
      end

      obj = klass.new
      interact = JsiiCalc::UsesInterfaceWithProperties.new(obj)
      expect(interact.just_read).to eq('READ_ONLY')
      expect(interact.write_and_read('Hello')).to eq('Hello')
    end

    it 'sync override can call super' do
      obj = SyncOverrides.new
      expect(obj.caller_is_property).to eq(10 * 5)
      obj.return_super = true
      expect(obj.caller_is_property).to eq(10 * 2)
    end

    it 'raises when double-async is called in sync override (method)' do
      obj = SyncOverrides.new
      obj.call_async = true

      expect { obj.caller_is_method }.to raise_error(Jsii::Error)
    end

    it 'raises when double-async is called in sync override (property getter)' do
      obj = SyncOverrides.new
      obj.call_async = true

      expect { obj.caller_is_property }.to raise_error(Jsii::Error)
    end

    it 'raises when double-async is called in sync override (property setter)' do
      obj = SyncOverrides.new
      obj.call_async = true

      expect { obj.caller_is_property = 12 }.to raise_error(Jsii::Error)
    end
  end
end
