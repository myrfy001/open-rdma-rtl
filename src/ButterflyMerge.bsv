import Vector :: *;
import ClientServer :: *;
import GetPut :: *;
import Connectable :: *;
import FIFOF :: *;

import FullyPipelinedUpdateBram :: *;
import BluerdmaConsts :: *;
import SdpBramWrapper :: *;

typedef 4 FourChannel;


typedef struct {
    tRowAddr rowAddr;
    tBankAddr bankAddr;
    tData data;
    tTag tag;
} ButterflyMergeReq#(type tRowAddr, type tBankAddr, type tData, type tTag) deriving(Bits);

typedef struct {
    tRowAddr rowAddr;
    tBankAddr bankAddr;
    tData data;
    tTag tag;
} ButterflyMergeResp#(type tRowAddr, type tBankAddr, type tData, type tTag) deriving(Bits);

typedef struct {
    tData data;
    tTag tag;
} ButterflyMergeRowContent#(type tData, type tTag) deriving(Bits);

typedef Server#(
    ButterflyMergeReq#(tRowAddr, tBankAddr, tData, tTag), 
    ButterflyMergeResp#(tRowAddr, tBankAddr, tData, tTag)
) ButterflyMergeServer#(type tRowAddr, type tBankAddr, type tData, type tTag);

interface FourChannelButterflyMerge#(type tRowAddr, type tBankAddr, type tData, type tTag, type tBramEntry);
    interface Vector#(FourChannel, ButterflyMergeServer#(tRowAddr, tBankAddr, tData, tTag)) mergeSrvs;
endinterface

module mkFourChannelButterflyMerge#(
        function Tuple2#(tTag, tData) updateLogic1(tTag oldTag, tData oldValue, tTag newTag, tData newValue),
        function Tuple2#(tTag, tData) updateLogic2(tTag oldTag, tData oldValue, tTag newTag, tData newValue)
    )(FourChannelButterflyMerge#(tRowAddr, tBankAddr, tData, tTag, tBramEntry)) provisos(
        Bits#(tRowAddr, szRowAddr),
        Bits#(tBankAddr, szBankAddr),
        Bits#(tData, szData),
        Bits#(tTag, szTag),
        Bits#(tBramEntry, szBramEntry),
        Eq#(tRowAddr),
        FShow#(tRowAddr),
        FShow#(tBramEntry),
        FShow#(Tuple2#(tRowAddr, tBramEntry)),
        PrimIndex#(tBankAddr, a__),
        Add#(b__, szRowAddr, ACX_BRAM72K_SDP_ADDR_WIDTH),
        Add#(c__, szBramEntry, BITS_COUNT_72K),
        Add#(d__, TAdd#(szTag, szData), szBramEntry)
    );
    
    function Tuple2#(tTag, tData) splitTagAndDataFromRawStorageContent(tBramEntry rawData);
        return unpack(truncate(pack(rawData)));
    endfunction

    function tBramEntry mergeTagAndDataFromRawStorageContent(tTag tag, tData value);
        return unpack(zeroExtend(pack(tuple2(tag, value))));
    endfunction

    function tBramEntry bramUpdateFunctionAdapter(Integer stageIdx, tBramEntry oldRawData, tBramEntry newRawData);
        let {oldTag, oldValue} = splitTagAndDataFromRawStorageContent(oldRawData);
        let {newTag, newValue} = splitTagAndDataFromRawStorageContent(newRawData);

        Tuple2#(tTag, tData) updatedEntry;
        if (stageIdx == 0) begin
            updatedEntry = updateLogic1(oldTag, oldValue, newTag, newValue);
        end
        else begin
            updatedEntry = updateLogic2(oldTag, oldValue, newTag, newValue);
        end

        let {updatedTag, updatedValue} = updatedEntry;
        return mergeTagAndDataFromRawStorageContent(updatedTag, updatedValue);
    endfunction



    Vector#(FourChannel, FullyPipelinedUpdateBram2#(tRowAddr, tBankAddr, tBramEntry)) firstStageBramVec <- replicateM(mkFullyPipelinedUpdateBram2(bramUpdateFunctionAdapter(0)));
    Vector#(FourChannel, FullyPipelinedUpdateBram2#(tRowAddr, tBankAddr, tBramEntry)) secondStageBramVec <- replicateM(mkFullyPipelinedUpdateBram2(bramUpdateFunctionAdapter(1)));

    Vector#(FourChannel, FIFOF#(ButterflyMergeResp#(tRowAddr, tBankAddr, tData, tTag))) outputFifoVec <- replicateM(mkFIFOF);
    Vector#(FourChannel, ButterflyMergeServer#(tRowAddr, tBankAddr, tData, tTag)) ifc;

    function ButterflyMergeServer#(tRowAddr, tBankAddr, tData, tTag) genInputPort(Integer chIdx1, Integer chIdx2);
        return (interface Server;
            interface Put request;
                method Action put(ButterflyMergeReq#(tRowAddr, tBankAddr, tData, tTag) req);
                    let bramReq1 = FullyPipelinedUpdateBramUpdateReq {
                        generateResp: True,
                        address:req.rowAddr,
                        bankAddress: req.bankAddr,
                        datain: mergeTagAndDataFromRawStorageContent(req.tag, req.data)
                    };

                    // req1 and req2 only different in generate resp or not.
                    let bramReq2 = bramReq1;
                    bramReq2.generateResp = False;

                    firstStageBramVec[chIdx1].updateSrv.request.put(bramReq1);
                    firstStageBramVec[chIdx2].updateSrv.request.put(bramReq2);
                endmethod
            endinterface

            interface response = toGet(outputFifoVec[chIdx1]);
        endinterface);
    endfunction

    ifc[0] = genInputPort(0, 1);
    ifc[1] = genInputPort(1, 0);
    ifc[2] = genInputPort(2, 3);
    ifc[3] = genInputPort(3, 2);
    
    interface mergeSrvs = ifc;
endmodule

