#pragma once

#include <memory>

struct SrtSocketStats {
  int64_t msTimeStamp;
  int64_t pktSentTotal;
  int64_t pktRecvTotal;
  int64_t pktSentUniqueTotal;
  int64_t pktRecvUniqueTotal;
  int32_t pktSndLossTotal;
  int32_t pktRcvLossTotal;
  int32_t pktRetransTotal;
  int32_t pktSentACKTotal;
  int32_t pktRecvACKTotal;
  int32_t pktSentNAKTotal;
  int32_t pktRecvNAKTotal;
  int64_t usSndDurationTotal;
  int32_t pktSndDropTotal;
  int32_t pktRcvDropTotal;
  int32_t pktRcvUndecryptTotal;
  int32_t pktSndFilterExtraTotal;
  int32_t pktRcvFilterExtraTotal;
  int32_t pktRcvFilterSupplyTotal;
  int32_t pktRcvFilterLossTotal;
  uint64_t byteSentTotal;
  uint64_t byteRecvTotal;
  uint64_t byteSentUniqueTotal;
  uint64_t byteRecvUniqueTotal;
  uint64_t byteRcvLossTotal;
  uint64_t byteRetransTotal;
  uint64_t byteSndDropTotal;
  uint64_t byteRcvDropTotal;
  uint64_t byteRcvUndecryptTotal;
  int64_t pktSent;
  int64_t pktRecv;
  int64_t pktSentUnique;
  int64_t pktRecvUnique;
  int32_t pktSndLoss;
  int32_t pktRcvLoss;
  int32_t pktRetrans;
  int32_t pktRcvRetrans;
  int32_t pktSentACK;
  int32_t pktRecvACK;
  int32_t pktSentNAK;
  int32_t pktRecvNAK;
  int32_t pktSndFilterExtra;
  int32_t pktRcvFilterExtra;
  int32_t pktRcvFilterSupply;
  int32_t pktRcvFilterLoss;
  double mbpsSendRate;
  double mbpsRecvRate;
  int64_t usSndDuration;
  int32_t pktReorderDistance;
  int64_t pktRcvBelated;
  int32_t pktSndDrop;
  int32_t pktRcvDrop;
};

std::unique_ptr<SrtSocketStats> readSrtSocketStats(int socket, bool clean_intervals);

