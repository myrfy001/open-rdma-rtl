import ClientServer :: *;
import BRAM :: *;
import FIFOF :: *;

import DataTypes :: *;
import RdmaUtils :: *;
import Headers :: *;

import Vector :: *;

import Settings :: *;
import MetaData :: *;
import PrimUtils :: *;

import Arbitration :: *;


interface QpContext;
    interface Server#(ReadReqQPC, Maybe#(EntryQPC)) querySrv;
    interface Server#(WriteReqQPC, Bool) updateSrv;
endinterface

(* synthesize *)
module mkQpContext(QpContext);
    QueuedServer#(ReadReqQPC, Maybe#(EntryQPC)) qpcQuerySrvInst <- mkQueuedServer("qpcQuerySrvInst");
    QueuedServer#(WriteReqQPC, Bool) qpcUpdateSrvInst <- mkQueuedServer("qpcUpdateSrvInst");

    RegFile#(IndexQP, Maybe#(EntryQPC)) qpcEntryCommonStorage <- mkRegFileFull;

    FIFOF#(Tuple2#(KeyQP, Maybe#(EntryQPC))) pipeQ <- mkFIFOF;

    rule handleReadReq;
        let req <- qpcQuerySrvInst.getReq;
        IndexQP idx = getIndexQP(req.qpn);
        KeyQP key   = getKeyQP(req.qpn);
        let qpcEntryMaybe = qpcEntryCommonStorage.sub(idx);
        keyPipeQ.enq(tuple2(key, qpcEntryMaybe));
        $display("read BRAM idx=", fshow(idx), "qpcEntryMaybe=", fshow(qpcEntryMaybe));
    endrule

    rule handleReadResp;
        let {key, qpcEntryMaybe} = keyPipeQ.first;
        keyPipeQ.deq;

        if (qpcEntryMaybe matches tagged Valid .resp &&& resp.qpnKeyPart == key) begin
            qpcQuerySrvInst.putResp(tagged Valid resp);
        end 
        else begin
            qpcQuerySrvInst.putResp(tagged Invalid);
        end
    endrule

    rule handleWriteReq;
        let req <- qpcUpdateSrvInst.getReq;
        IndexQP idx = getIndexQP(req.qpn);

        qpcEntryCommonStorage.upd(idx, req.ent);
        qpcUpdateSrvInst.putResp(True);

        $display("write BRAM idx=", fshow(idx), "req=", fshow(req.ent));
    endrule

    interface querySrv = qpcQuerySrvInst.srv;
    interface updateSrv = qpcUpdateSrvInst.srv;
endmodule



interface Server2Client#(type tReq, type tResp);
    interface Server#(tReq, tResp) srv;
    interface Client#(tReq, tResp) clt;
endinterface

module mkServer2Client(Server2Client#(tReq, tResp)) provisos (
        Bits#(tReq, szReq),
        Bits#(tResp, szResp)
    );

    interface Server srv;
        interface Put request;
            method Action put(tReq req);
            endmethod
        endinterface

        interface Gut response;
            method ActionValue#(tResp) get;
            endmethod
        endinterface
    endinterface

    interface Client clt;
        interface Put response;
            method Action put(tResp resp);
            endmethod
        endinterface

        interface Gut request;
            method ActionValue#(tReq) get;
            endmethod
        endinterface
    endinterface

endmodule


interface QpContextTwoWayQuery;
    interface Vector#(NUMERIC_TYPE_TWO, Server#(ReadReqQPC, Maybe#(EntryQPC))) querySrv;
    interface Server#(WriteReqQPC, Bool) updateSrv;
endinterface



(* synthesize *)
module mkQpContextTwoWayQuery(QpContextTwoWayQuery);
    
    function Bool alwaysTrue(anytype resp);
        return True;
    endfunction

    QpContext qpContext <- mkQpContext;

    Vector#(NUMERIC_TYPE_TWO, RingbufDmaH2cClt) dmaAccessH2cCltVec = newVector;

    let arbitratedClient <- mkClientArbiter(
        "QpContextTwoWayQuery",
        False,
        2,
        dmaAccessH2cCltVec,
        alwaysTrue,
        alwaysTrue
    );

    

    interface querySrv = qpcQuerySrvInst.srv;
    interface updateSrv = qpContext.updateSrv;
endmodule