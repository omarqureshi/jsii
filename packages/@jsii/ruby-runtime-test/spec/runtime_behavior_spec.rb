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

  describe 'Isomorphism' do
    it 'isomorphism within constructor' do
      klass = Class.new(JsiiCalc::Isomorphism) do
        include RSpec::Matchers
        def initialize
          super
          expect(self).to be(self.myself)
        end
      end
      klass.new
    end
  end
  describe 'JsiiAgent' do
    it 'reports Ruby language and version' do
      # The kernel sets JSII_AGENT=Ruby/<version> on spawn, so this should
      # always be populated.  If it's not, the runtime regressed and we want
      # to know loudly — no `skip` fallback.
      expect(JsiiCalc::JsiiAgent.value).to match(/^Ruby\/\d+\.\d+\.\d+/)
    end
  end
  describe 'Node standard library' do
    it 'exposes fs, os, and crypto' do
      obj = JsiiCalc::NodeStandardLibrary.new
      expect(obj.fs_read_file).to eq('Hello, resource!')
      expect(obj.fs_read_file_sync).to eq('Hello, resource! SYNC!')
      expect(obj.os_platform.length).to be > 0
      expect(obj.crypto_sha256).to eq('6a2da20943931e9834fc12cfe5bb47bbd9ae43489a30726962b576f4e3993e50')
    end
  end
  describe 'Object ID stability' do
    it 'does not reallocate object id when constructor passes this out' do
      klass = Class.new(JsiiCalc::PartiallyInitializedThisConsumer) do
        include RSpec::Matchers
        def consume_partially_initialized_this(obj, dt, ev)
          expect(obj).not_to be_nil
          expect(dt).to be_a(DateTime)
          expect(ev).to eq(JsiiCalc::AllTypesEnum::THIS_IS_GREAT)
          'OK'
        end
      end

      reflector = klass.new
      obj = JsiiCalc::ConstructorPassesThisOut.new(reflector)
      expect(obj).not_to be_nil
    end
  end
  describe 'ISO8601 / date deserialization safety' do
    it 'ISO8601 strings are NOT auto-deserialized as dates' do
      wall_clock_class = Class.new do
        include JsiiCalc::IWallClock
        def initialize(now)
          @now = now
        end
        def iso8601_now
          @now
        end
      end

      entropy_class = Class.new(JsiiCalc::Entropy) do
        def repeat(word)
          word
        end
      end

      now = DateTime.now.new_offset(0).iso8601(3).sub('+00:00', 'Z')
      wall_clock = wall_clock_class.new(now)
      entropy = entropy_class.new(wall_clock)

      expect(entropy.increase).to eq(now)
    end
  end
  describe 'Exception message propagation' do
    it 'propagates error message from JS' do
      # AcceptsPath is in the cdk22369 submodule.  The submodule is in the
      # jsii-calc assembly, so a missing constant means the generator dropped
      # it — fail loudly rather than silently passing.
      expect { JsiiCalc::Cdk22369::AcceptsPath.new(source_path: 'A Bad Path') }.to raise_error(Jsii::RuntimeError, /Cannot find asset/)
    end
  end
end
