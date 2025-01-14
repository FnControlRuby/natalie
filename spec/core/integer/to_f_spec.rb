require_relative '../../spec_helper'

describe "Integer#to_f" do
  context "fixnum" do
    it "returns self converted to a Float" do
      0.to_f.should == 0.0
      -500.to_f.should == -500.0
      9_641_278.to_f.should == 9641278.0
    end
  end

  context "bignum" do
    it "returns self converted to a Float" do
      bignum_value(0x4000_0aa0_0bb0_0000).to_f.should eql(13_835_069_737_789_292_544.00)
      bignum_value(0x8000_0000_0000_0ccc).to_f.should eql(18_446_744_073_709_555_712.00)
      (-bignum_value(99)).to_f.should eql(-9_223_372_036_854_775_808.00)
    end

    it "converts number close to Float::MAX without exceeding MAX or producing NaN" do
      # NATFIXME: Implement Integer#** to support overflows to bignums
      # (10**308).to_f.should == 10.0 ** 308
      x = 10
      307.times { x *= 10 }
      x.to_f.should == 10.0 ** 308
    end
  end
end
