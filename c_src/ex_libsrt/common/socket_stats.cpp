#include "socket_stats.h"
#include <srt/srt.h>

std::unique_ptr<SocketStats> readSocketStats(int socket, bool clean_intervals) {
  SRT_TRACEBSTATS trace;

  int result = srt_bstats(socket, &trace, (int)clean_intervals);
  if (result != 0) {
    return nullptr;
  }

  auto stats = std::make_unique<SocketStats>();

  stats->msTimeStamp = trace.msTimeStamp;
  stats->pktSentTotal = trace.pktSentTotal;
  stats->pktRecvTotal = trace.pktRecvTotal;
  stats->pktSentUniqueTotal = trace.pktSentUniqueTotal;
  stats->pktRecvUniqueTotal = trace.pktRecvUniqueTotal;
  stats->pktSndLossTotal = trace.pktSndLossTotal;
  stats->pktRcvLossTotal = trace.pktRcvLossTotal;
  stats->pktRetransTotal = trace.pktRetransTotal;
  stats->pktSentACKTotal = trace.pktSentACKTotal;
  stats->pktRecvACKTotal = trace.pktRecvACKTotal;
  stats->pktSentNAKTotal = trace.pktSentNAKTotal;
  stats->pktRecvNAKTotal = trace.pktRecvNAKTotal;
  stats->usSndDurationTotal = trace.usSndDurationTotal;
  stats->pktSndDropTotal = trace.pktSndDropTotal;
  stats->pktRcvDropTotal = trace.pktRcvDropTotal;
  stats->pktRcvUndecryptTotal = trace.pktRcvUndecryptTotal;
  stats->pktSndFilterExtraTotal = trace.pktSndFilterExtraTotal;
  stats->pktRcvFilterExtraTotal = trace.pktRcvFilterExtraTotal;
  stats->pktRcvFilterSupplyTotal = trace.pktRcvFilterSupplyTotal;
  stats->pktRcvFilterLossTotal = trace.pktRcvFilterLossTotal;
  stats->byteSentTotal = trace.byteSentTotal;
  stats->byteRecvTotal = trace.byteRecvTotal;
  stats->byteSentUniqueTotal = trace.byteSentUniqueTotal;
  stats->byteRecvUniqueTotal = trace.byteRecvUniqueTotal;
  stats->byteRcvLossTotal = trace.byteRcvLossTotal;
  stats->byteRetransTotal = trace.byteRetransTotal;
  stats->byteSndDropTotal = trace.byteSndDropTotal;
  stats->byteRcvDropTotal = trace.byteRcvDropTotal;
  stats->byteRcvUndecryptTotal = trace.byteRcvUndecryptTotal;
  stats->pktSent = trace.pktSent;
  stats->pktRecv = trace.pktRecv;
  stats->pktSentUnique = trace.pktSentUnique;
  stats->pktRecvUnique = trace.pktRecvUnique;
  stats->pktSndLoss = trace.pktSndLoss;
  stats->pktRcvLoss = trace.pktRcvLoss;
  stats->pktRetrans = trace.pktRetrans;
  stats->pktRcvRetrans = trace.pktRcvRetrans;
  stats->pktSentACK = trace.pktSentACK;
  stats->pktRecvACK = trace.pktRecvACK;
  stats->pktSentNAK = trace.pktSentNAK;
  stats->pktRecvNAK = trace.pktRecvNAK;
  stats->pktSndFilterExtra = trace.pktSndFilterExtra;
  stats->pktRcvFilterExtra = trace.pktRcvFilterExtra;
  stats->pktRcvFilterSupply = trace.pktRcvFilterSupply;
  stats->pktRcvFilterLoss = trace.pktRcvFilterLoss;
  stats->mbpsSendRate = trace.mbpsSendRate;
  stats->mbpsRecvRate = trace.mbpsRecvRate;
  stats->usSndDuration = trace.usSndDuration;
  stats->pktReorderDistance = trace.pktReorderDistance;
  stats->pktRcvBelated = trace.pktRcvBelated;
  stats->pktSndDrop = trace.pktSndDrop;
  stats->pktRcvDrop = trace.pktRcvDrop;

  return stats;
}
