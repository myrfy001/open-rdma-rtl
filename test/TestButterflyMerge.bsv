import ButterflyMerge :: *;
import SdpBramWrapper :: *;

function Tuple2#(Bit#(15), Bit#(128)) mergeFuncBitOr(Bit#(15) oldTag, Bit#(128) oldData, Bit#(15) newTag, Bit#(128) newData);
    if (oldTag == newTag) begin
        return tuple2(oldTag, oldData | newData);
    end 
    else begin
        return tuple2(newTag, newData);
    end
endfunction

(* doc = "testcase" *)
module mkTestFourChannelButterflyMergeCreateInstance(Empty);
    FourChannelButterflyMerge#(Bit#(5), Bit#(2), Bit#(128), Bit#(15), Bram72kEntry144) instWithFourBank <- mkFourChannelButterflyMerge(mergeFuncBitOr, mergeFuncBitOr);

    // The following instance has a bankAddr type of `Bit#(0)`, which is of zero size, make sure it works.
    FourChannelButterflyMerge#(Bit#(5), Bit#(0), Bit#(128), Bit#(15), Bram72kEntry144) instWithOneBank <- mkFourChannelButterflyMerge(mergeFuncBitOr, mergeFuncBitOr);
endmodule

