import Vector :: *;
import BRAM :: *;

import BluerdmaConsts :: *;
import ConnectableF :: *;

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

interface FourChannelButterflyMerge#(type tRowAddr, type tBankAddr, type tData, type tTag);
    // interface Vector#(FourChannel, 
    //     ServerP#(
    //         ButterflyMergeReq#(tRowAddr, tBankAddr, tData, tTag), 
    //         ButterflyMergeResp#(tRowAddr, tBankAddr, tData, tTag)
    //         )) reuqests;
endinterface

module mkFourChannelButterflyMerge(FourChannelButterflyMerge#(tRowAddr, tBankAddr, tData, tTag)) provisos(
        Bits#(tRowAddr, szRowAddr),
        Bits#(tBankAddr, szBankAddr),
        Bits#(tData, szData),
        Bits#(tTag, szTag)
    );
    BRAM_Configure cfg = defaultValue;
    cfg.latency = valueOf(BRAM_LATENCY_TWO_CYCLE);
    // outFIFODepth is (latency + 2) cycles to make it fully pipeline.
    cfg.outFIFODepth = valueOf(BRAM_LATENCY_TWO_CYCLE) + 2;
    Vector#(TExp#(szBankAddr), BRAM1Port#(tRowAddr, ButterflyMergeRowContent#(tData, tTag))) firstStageBramVec <- replicateM(mkBRAM1Server (cfg));
    Vector#(TExp#(szBankAddr), BRAM1Port#(tRowAddr, ButterflyMergeRowContent#(tData, tTag))) secondStageBramVec <- replicateM(mkBRAM1Server (cfg));


endmodule

