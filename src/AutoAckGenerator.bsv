import PsnContinousChecker :: *;

typedef struct {
    PSN psn;
    QPN qpn;
    Bool needAck;
} PsnContinousCheckerReq deriving(Bits, FShow);


interface AutoAckGenerator;
    interface Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(PsnContinousCheckerReq)) reqPipeInVec;
endinterface


(* synthesize *)
module mkAutoAckGenerator(AutoAckGenerator);
    Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(PsnContinousCheckerReq)) reqPipeInVecInst = newVector;
    Vector#(CPSN_CHECKER_CHANNEL_NUM, FIFOF#(PsnContinousCheckerReq)) reqPipeInQueueVec <- replicateM(mkFIFOF);


    FourChannelPsnBitmapPreMerge allPacketPsnPermerge <- mkFourChannelPsnBitmapPreMerge;
    FourChannelPsnBitmapPreMerge needAckPacketPsnPermerge <- mkFourChannelPsnBitmapPreMerge;

    BitmapWindowStorage#(IndexQP, OooWindowBitmap, PsnMergeWindowBoundary, OOO_WINDOW_STRIDE) allPacketPsnBitmapStorage <- mkBitmapWindowStorage("init_bram_psn_merge_storage.bin");
    BitmapWindowStorage#(IndexQP, OooWindowBitmap, PsnMergeWindowBoundary, OOO_WINDOW_STRIDE) needAckPacketPsnBitmapStorage <- mkBitmapWindowStorage("init_bram_psn_merge_storage.bin");

    Reg#(Bool) forwardToStorageEvenOddReg <- mkReg(True);

    Vector#(NUMERIC_TYPE_TWO, CpsnCounter#(OooWindowBitmap, PsnMergeWindowBoundary, OOO_WINDOW_STRIDE)) cpsnCounterVec <- replicateM(mkCpsnCounter);

    for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
        rule forwardInputReqToPsnPreMerge;
            let req = reqPipeInQueueVec[idx].first;
            reqPipeInQueueVec[idx].deq;

            let preMergeReq = FourChannelPsnBitmapPreMergeReq {
                psn: req.psn,
                qpn: req.qpn
            };

            allPacketPsnPermerge.reqPipeInVec[idx].enq(preMergeReq);
            if (req.needAck) begin
                needAckPacketPsnPermerge.reqPipeInVec[idx].enq(preMergeReq);
            end
        endrule
    endrule


    rule forwardPremergeToStorage;
        forwardToStorageEvenOddReg <= !forwardToStorageEvenOddReg;

        let allPacketStorageResp = allPacketPsnBitmapStorage.respPipeOut.first;
        let needAckPacketStorageResp = needAckPacketPsnBitmapStorage.respPipeOut.first;

        if (forwardToStorageEvenOddReg) begin
            if (allPacketStorageResp[0] matches tagged Valid .req) begin
                allPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });
               
            end
            else begin
                allPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Invalid);
            end

            if (allPacketStorageResp[1] matches tagged Valid .req) begin
                allPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });

            end
            else begin
                allPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Invalid);
            end

            if (needAckPacketStorageResp[0] matches tagged Valid .req) begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });
               
            end
            else begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Invalid);
            end

            if (needAckPacketStorageResp[1] matches tagged Valid .req) begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });

            end
            else begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Invalid);
            end
        end
        else begin
            if (allPacketStorageResp[2] matches tagged Valid .req) begin
                allPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });

            end
            else begin
                allPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Invalid);
            end

            if (allPacketStorageResp[3] matches tagged Valid .req) begin
                allPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });

            end
            else begin
                allPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Invalid);
            end

            if (needAckPacketStorageResp[2] matches tagged Valid .req) begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });

            end
            else begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Invalid);
            end

            if (needAckPacketStorageResp[3] matches tagged Valid .req) begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });

            end
            else begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Invalid);
            end

            allPacketPsnBitmapStorage.respPipeOut.deq;
            needAckPacketPsnBitmapStorage.respPipeOut.deq;
        end
    endrule


//     typedef struct {
//     tRowAddr                                    rowAddr;
//     Bool                                        isShiftWindow;
//     Bool                                        isShiftOutOfBoundary;
//     tData                                       windowShiftedOutData;
//     BitmapWindowStorageEntry#(tData, tBoundary) oldEntry;
//     BitmapWindowStorageEntry#(tData, tBoundary) newEntry;
// } BitmapWindowStorageUpdateResp#(type tRowAddr, type tData, type tBoundary) deriving(Bits, FShow);


    rule forwardPsnBitmapStorageOutputToCpsnCounter;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let psnBitmapStorageOutputMaybe = allPacketPsnBitmapStorage.respPipeOutVec[idx].first;
            allPacketPsnBitmapStorage.respPipeOutVec[idx].deq;

            if (psnBitmapStorageOutputMaybe matches tagged Valid .psnBitmapStorageOutput) begin
                let cpsnCountReq = CpsnCounterReq {
                    bitmapEntry: psnBitmapStorageOutput.newEntry
                };
                cpsnCounterVec[idx].reqPipeIn.enq(cpsnCountReq);
            end
        end 
    endrule

    for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
        reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
    end
    interface reqPipeInVec = reqPipeInVecInst;
endmodule
