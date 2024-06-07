import ButterflyMerge :: *;

(* doc = "testcase" *)
module mkTestFourChannelButterflyMergeCreateInstance(Empty);
    FourChannelButterflyMerge#(Bit#(5), Bit#(2), Bit#(128), Bit#(15)) instWithFourBank <- mkFourChannelButterflyMerge;

    // The following instance has a bankAddr type of `Bit#(0)`, which is of zero size, make sure it works.
    FourChannelButterflyMerge#(Bit#(5), Bit#(0), Bit#(128), Bit#(15)) instWithOneBank <- mkFourChannelButterflyMerge;
endmodule

