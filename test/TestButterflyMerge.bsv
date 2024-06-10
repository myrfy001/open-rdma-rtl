import ClientServer :: *;
import GetPut :: *;

import Utils4Test :: *;

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

    rule exit;
        $finish;
    endrule
endmodule

(* doc = "testcase" *)
module mkTestFourChannelButterflyMergeSingleBeatTest(Empty);

    let stopCounter <- mkSimulationCycleLimitCounter(200);

    FourChannelButterflyMerge#(Bit#(5), Bit#(2), Bit#(128), Bit#(15), Bram72kEntry144) instWithFourBank <- mkFourChannelButterflyMerge(mergeFuncBitOr, mergeFuncBitOr);

    // The boundary case, every 2 beat comes a packet
    rule sendOneBeatReq if (stopCounter % 2 == 0);
        $display("$time=%0t, Enq req", $time);
        for (Integer idx = 0; idx < 4; idx = idx + 1) begin
            instWithFourBank.mergeSrvs[idx].request.put(ButterflyMergeReq{
                rowAddr: 0,
                bankAddr: 0,
                data: 1 << idx,
                tag: 0
            });
        end
    endrule

    for (Integer idx = 0; idx < 4; idx = idx + 1) begin
        rule displayResp;
            let resp <- instWithFourBank.mergeSrvs[idx].response.get;
            $display("$time=%0t, ", $time, fshow(resp));
        endrule
    end

endmodule