import ClientServer :: *;
import GetPut :: *;
import FIFOF :: *;
import Connectable :: *;

import DataTypes :: *;
import RdmaUtils :: *;
import RdmaHeaders :: *;

import Vector :: *;

import Settings :: *;
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

    AutoInferBram#(IndexQP, Maybe#(EntryQPC)) qpcEntryCommonStorage <- mkAutoInferBram;

    FIFOF#(Tuple2#(IndexQP, KeyQP)) pipeQ <- mkFIFOF;

    rule handleReadReq;
        let req <- qpcQuerySrvInst.getReq;
        IndexQP idx = getIndexQP(req.qpn);
        KeyQP key   = getKeyQP(req.qpn);
        qpcEntryCommonStorage.putReadReq(idx);
        pipeQ.enq(tuple2(idx, key));
    endrule

    rule handleReadResp;
        let {idx, key} = pipeQ.first;
        pipeQ.deq;
        let qpcEntryMaybe <- qpcEntryCommonStorage.getReadResp;

        if (qpcEntryMaybe matches tagged Valid .resp &&& resp.qpnKeyPart == key) begin
            qpcQuerySrvInst.putResp(tagged Valid resp);
        end 
        else begin
            qpcQuerySrvInst.putResp(tagged Invalid);
        end
        $display("read BRAM idx=", fshow(idx), "qpcEntryMaybe=", fshow(qpcEntryMaybe));
    endrule

    rule handleWriteReq;
        let req <- qpcUpdateSrvInst.getReq;
        IndexQP idx = getIndexQP(req.qpn);

        qpcEntryCommonStorage.write(idx, req.ent);
        qpcUpdateSrvInst.putResp(True);

        $display("write BRAM idx=", fshow(idx), "req=", fshow(req.ent));
    endrule

    interface querySrv = qpcQuerySrvInst.srv;
    interface updateSrv = qpcUpdateSrvInst.srv;
endmodule



interface QpContextTwoWayQuery;
    interface Vector#(NUMERIC_TYPE_TWO, Server#(ReadReqQPC, Maybe#(EntryQPC))) querySrvVec;
    interface Server#(WriteReqQPC, Bool) updateSrv;
endinterface



(* synthesize *)
module mkQpContextTwoWayQuery(QpContextTwoWayQuery);
    
    function Bool alwaysTrue(anytype resp);
        return True;
    endfunction

    QpContext qpContext <- mkQpContext;

    Vector#(NUMERIC_TYPE_TWO, Server2Client#(ReadReqQPC, Maybe#(EntryQPC))) srvToCltConvertVec <- replicateM(mkServer2ClientSignleBeat);
    Vector#(NUMERIC_TYPE_TWO, Server#(ReadReqQPC, Maybe#(EntryQPC))) querySrvVecInst = newVector;
    Vector#(NUMERIC_TYPE_TWO, Client#(ReadReqQPC, Maybe#(EntryQPC))) queryCltVecInst = newVector;

    querySrvVecInst[0] = srvToCltConvertVec[0].srv;
    querySrvVecInst[1] = srvToCltConvertVec[1].srv;

    queryCltVecInst[0] = srvToCltConvertVec[0].clt;
    queryCltVecInst[1] = srvToCltConvertVec[1].clt;
    

    let arbitratedClient <- mkClientArbiter(
        "QpContextTwoWayQuery",
        False,
        2,
        queryCltVecInst,
        alwaysTrue,
        alwaysTrue
    );

    mkConnection(arbitratedClient, qpContext.querySrv);

    interface querySrvVec = querySrvVecInst;
    interface updateSrv = qpContext.updateSrv;
endmodule



interface QpContextFourWayQuery;
    interface Vector#(NUMERIC_TYPE_FOUR, Server#(ReadReqQPC, Maybe#(EntryQPC))) querySrvVec;
    interface Server#(WriteReqQPC, Bool) updateSrv;
endinterface

(* synthesize *)
module mkQpContextFourWayQuery(QpContextFourWayQuery);
    

    Vector#(NUMERIC_TYPE_TWO, QpContextTwoWayQuery) twoWayQpContextVec <- replicateM(mkQpContextTwoWayQuery);

    Vector#(NUMERIC_TYPE_FOUR, Server2Client#(ReadReqQPC, Maybe#(EntryQPC))) srvToCltConvertVec <- replicateM(mkServer2ClientSignleBeat);
    Vector#(NUMERIC_TYPE_FOUR, Server#(ReadReqQPC, Maybe#(EntryQPC))) querySrvVecInst = newVector;
    Vector#(NUMERIC_TYPE_FOUR, Client#(ReadReqQPC, Maybe#(EntryQPC))) queryCltVecInst = newVector;

    querySrvVecInst[0] = srvToCltConvertVec[0].srv;
    querySrvVecInst[1] = srvToCltConvertVec[1].srv;
    querySrvVecInst[2] = srvToCltConvertVec[2].srv;
    querySrvVecInst[3] = srvToCltConvertVec[3].srv;
    
    mkConnection(srvToCltConvertVec[0].clt, twoWayQpContextVec[0].querySrvVec[0]);
    mkConnection(srvToCltConvertVec[1].clt, twoWayQpContextVec[0].querySrvVec[1]);
    mkConnection(srvToCltConvertVec[2].clt, twoWayQpContextVec[1].querySrvVec[0]);
    mkConnection(srvToCltConvertVec[3].clt, twoWayQpContextVec[1].querySrvVec[1]);

    interface querySrvVec = querySrvVecInst;

    interface Server updateSrv;
        interface Put request;
            method Action put(WriteReqQPC req);
                twoWayQpContextVec[0].updateSrv.request.put(req);
                twoWayQpContextVec[1].updateSrv.request.put(req);
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(Bool) get;
                let resp <- twoWayQpContextVec[0].updateSrv.response.get;
                let _ <- twoWayQpContextVec[1].updateSrv.response.get;
                // two QpContextTwoWayQuery should be in sync, so only care one's response is enough.
                return resp;
            endmethod
        endinterface
    endinterface
endmodule