require "spec_helper"

module Wasmtime
  RSpec.describe Func do
    it "calls the passed-in proc proc" do
      runs = 0
      func = build_func([], [], -> { runs += 1 })
      expect { func.call([]) }.to change { runs }.by(1)
      expect { func.call([]) }.to change { runs }.by(1)
    end

    it "accepts any callable" do
      callable = Class.new do
        def call
        end
      end

      build_func([], [], -> {}).call([])
      build_func([], [], callable.new).call([])
      build_func([], [], method(:noop)).call([])
    end

    it "accepts block" do
      store = Store.new(engine, {})
      func = Func.new(store, FuncType.new([], [])) {}
      func.call([])
    end

    it "accepts block and nil proc argument" do
      store = Store.new(engine, {})
      func = Func.new(store, FuncType.new([], []), nil) {}
      func.call([])
    end

    it "raises without proc or block" do
      expect { build_func([], []) }
        .to raise_error(ArgumentError)
    end

    it "raises with both proc and block" do
      expect { build_func([], [], -> {}) {} }
        .to raise_error(ArgumentError)
    end

    it("converts i32 back and forth") { expect(roundtrip_value(:i32, 4)).to eq(4) }
    it("converts i64 back and forth") { expect(roundtrip_value(:i64, 2**40)).to eq(2**40) }
    it("converts f32 back and forth") { expect(roundtrip_value(:f32, 5.5)).to eq(5.5) }
    it("converts f64 back and forth") { expect(roundtrip_value(:f64, 5.5)).to eq(5.5) }
    it("converts nil externref back and forth") { expect(roundtrip_value(:externref, nil)).to be_nil }
    it("converts string externref back and forth") { expect(roundtrip_value(:externref, "foo")).to eq("foo") }

    it "converts BasicObject externref back and forth" do
      obj = BasicObject
      expect(roundtrip_value(:externref, obj)).to equal(obj)
    end

    it "converts ref.null into nil" do
      instance = compile(<<~WAT)
        (module
          (func (export "main") (result externref)
            ref.null extern))
      WAT
      expect(instance.invoke("main", [])).to be_nil
    end

    it "ignores the proc's return value when func has no results" do
      func = build_func([], [], -> { 1 })
      expect(func.call([])).to be_nil
    end

    it "accepts array of 1 element for single result" do
      func = build_func([], [:i32], -> { [1] })
      expect(func.call([])).to eq(1)
    end

    it "rejects mismatching results size" do
      func = build_func([], [:i32], -> { [1, 2] })
      expect { func.call([]) }.to raise_error(Wasmtime::Error, /wrong number of results \(given 2, expected 1\)/)
    end

    it "rejects mismatching result type" do
      func = build_func([], [:i32], -> { [nil] })
      expect { func.call([]) }.to raise_error(Wasmtime::Error)
    end

    it "tells you which result failed to convert in the error message" do
      skip("TODO!")
    end

    it "rejects mismatching params size" do
      func = build_func([:i32], [], ->(_, _) {})
      expect { func.call([1]) }.to raise_error(ArgumentError, /wrong number of arguments \(given 1, expected 2\)/)
    end

    it "bubbles the exception on with call" do
      error_class = Class.new(StandardError)
      func = build_func([], [], -> { raise error_class })
      expect { func.call([]) }.to raise_error(error_class)
      # Run a second time to catch already borrowed issues
      expect { func.call([]) }.to raise_error(error_class)
    end

    it "bubbles the exception on start" do
      error_class = Class.new(StandardError)
      func = Func.new(store, FuncType.new([], []), -> { raise error_class })
      mod = Wasmtime::Module.new(engine, <<~WAT)
        (module
          (import "" "" (func))
          (start 0))
      WAT

      expect { Wasmtime::Instance.new(store, mod, [func]) }
        .to raise_error(error_class)
    end

    it "re-enters into Wasm from Ruby" do
      called = false
      func1 = Func.new(store, FuncType.new([], []), -> { called = true })
      func2 = Func.new(store, FuncType.new([], []), -> { func1.call([]) })
      func2.call([])
      expect(called).to be true
    end

    it "does not send the caller when func has caller: false" do
      called = false
      body = ->(*args) do
        called = true
        expect(args.size).to eq(0)
      end

      func = Func.new(
        Store.new(engine, {}),
        FuncType.new([], []),
        body,
        caller: false
      )
      func.call([])
      expect(called).to be true
    end

    it "sends caller as first argument when func has caller: true" do
      called = false
      store_data = BasicObject.new
      body = ->(caller, _) do
        called = true
        expect(caller).to be_instance_of(Caller)
        expect(caller.store_data).to equal(store_data)
      end

      func = Func.new(
        Store.new(engine, store_data),
        FuncType.new([:i32], []),
        body,
        caller: true
      )
      func.call([1])
      expect(called).to be true
    end

    private

    def roundtrip_value(type, value)
      build_func([type], [type], ->(arg) { arg })
        .call([value])
    end

    def build_func(params, results, impl = nil, &block)
      store = Store.new(engine, {})
      Func.new(store, FuncType.new(params, results), impl, &block)
    end

    # Used to test that you can send a `Method` object with `method(:foo)`
    def noop
    end
  end
end
