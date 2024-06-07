import Vector :: *;
import ClientServer :: *;
import GetPut :: *;
import Connectable :: *;

import FullyPipelinedUpdateBram :: *;
import BluerdmaConsts :: *;


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
    interface Vector#(FourChannel, 
        Server#(
            ButterflyMergeReq#(tRowAddr, tBankAddr, tData, tTag), 
            ButterflyMergeResp#(tRowAddr, tBankAddr, tData, tTag)
            )) reuqests;
endinterface

module mkFourChannelButterflyMerge#(
        function tData updateLogic1(tData oldValue, tData newValue),
        function tData updateLogic2(tData oldValue, tData newValue)
    )(FourChannelButterflyMerge#(tRowAddr, tBankAddr, tData, tTag)) provisos(
        Bits#(tRowAddr, szRowAddr),
        Bits#(tBankAddr, szBankAddr),
        Bits#(tData, szData),
        Bits#(tTag, szTag)
    );
    
    Vector#(FourChannel, FullyPipelinedUpdateBram2#(Addr, tBankAddr, tData)) firstStageBramVec <- replicateM(mkFullyPipelinedUpdateBram2(updateLogic1));
    Vector#(FourChannel, FullyPipelinedUpdateBram2#(Addr, tBankAddr, tData)) secondStageBramVec <- replicateM(mkFullyPipelinedUpdateBram2(updateLogic2));

    function genInputPort(Integer ch1, Integer ch2);
        interface 
    endfunction

endmodule

