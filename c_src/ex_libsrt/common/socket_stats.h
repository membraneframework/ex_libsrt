#pragma once

#include <fine.hpp>

#include <memory>

namespace atoms {
static auto ElixirSocketStats = fine::Atom("Elixir.ExLibSRT.SocketStats");
static auto msTimeStamp = fine::Atom("msTimeStamp");
static auto pktSentTotal = fine::Atom("pktSentTotal");
static auto pktRecvTotal = fine::Atom("pktRecvTotal");
static auto pktSentUniqueTotal = fine::Atom("pktSentUniqueTotal");
static auto pktRecvUniqueTotal = fine::Atom("pktRecvUniqueTotal");
static auto pktSndLossTotal = fine::Atom("pktSndLossTotal");
static auto pktRcvLossTotal = fine::Atom("pktRcvLossTotal");
static auto pktRetransTotal = fine::Atom("pktRetransTotal");
static auto pktRcvRetransTotal = fine::Atom("pktRcvRetransTotal");
static auto pktSentACKTotal = fine::Atom("pktSentACKTotal");
static auto pktRecvACKTotal = fine::Atom("pktRecvACKTotal");
static auto pktSentNAKTotal = fine::Atom("pktSentNAKTotal");
static auto pktRecvNAKTotal = fine::Atom("pktRecvNAKTotal");
static auto usSndDurationTotal = fine::Atom("usSndDurationTotal");
static auto pktSndDropTotal = fine::Atom("pktSndDropTotal");
static auto pktRcvDropTotal = fine::Atom("pktRcvDropTotal");
static auto pktRcvUndecryptTotal = fine::Atom("pktRcvUndecryptTotal");
static auto pktSndFilterExtraTotal = fine::Atom("pktSndFilterExtraTotal");
static auto pktRcvFilterExtraTotal = fine::Atom("pktRcvFilterExtraTotal");
static auto pktRcvFilterSupplyTotal = fine::Atom("pktRcvFilterSupplyTotal");
static auto pktRcvFilterLossTotal = fine::Atom("pktRcvFilterLossTotal");
static auto byteSentTotal = fine::Atom("byteSentTotal");
static auto byteRecvTotal = fine::Atom("byteRecvTotal");
static auto byteSentUniqueTotal = fine::Atom("byteSentUniqueTotal");
static auto byteRecvUniqueTotal = fine::Atom("byteRecvUniqueTotal");
static auto byteRcvLossTotal = fine::Atom("byteRcvLossTotal");
static auto byteRetransTotal = fine::Atom("byteRetransTotal");
static auto byteSndDropTotal = fine::Atom("byteSndDropTotal");
static auto byteRcvDropTotal = fine::Atom("byteRcvDropTotal");
static auto byteRcvUndecryptTotal = fine::Atom("byteRcvUndecryptTotal");
static auto pktSent = fine::Atom("pktSent");
static auto pktRecv = fine::Atom("pktRecv");
static auto pktSentUnique = fine::Atom("pktSentUnique");
static auto pktRecvUnique = fine::Atom("pktRecvUnique");
static auto pktSndLoss = fine::Atom("pktSndLoss");
static auto pktRcvLoss = fine::Atom("pktRcvLoss");
static auto pktRetrans = fine::Atom("pktRetrans");
static auto pktRcvRetrans = fine::Atom("pktRcvRetrans");
static auto pktSentACK = fine::Atom("pktSentACK");
static auto pktRecvACK = fine::Atom("pktRecvACK");
static auto pktSentNAK = fine::Atom("pktSentNAK");
static auto pktRecvNAK = fine::Atom("pktRecvNAK");
static auto pktSndFilterExtra = fine::Atom("pktSndFilterExtra");
static auto pktRcvFilterExtra = fine::Atom("pktRcvFilterExtra");
static auto pktRcvFilterSupply = fine::Atom("pktRcvFilterSupply");
static auto pktRcvFilterLoss = fine::Atom("pktRcvFilterLoss");
static auto mbpsSendRate = fine::Atom("mbpsSendRate");
static auto mbpsRecvRate = fine::Atom("mbpsRecvRate");
static auto usSndDuration = fine::Atom("usSndDuration");
static auto pktReorderDistance = fine::Atom("pktReorderDistance");
static auto pktRcvBelated = fine::Atom("pktRcvBelated");
static auto pktSndDrop = fine::Atom("pktSndDrop");
static auto pktRcvDrop = fine::Atom("pktRcvDrop");
} // namespace atoms

struct SocketStats {
  int64_t msTimeStamp;
  int64_t pktSentTotal;
  int64_t pktRecvTotal;
  int64_t pktSentUniqueTotal;
  int64_t pktRecvUniqueTotal;
  int64_t pktSndLossTotal;
  int64_t pktRcvLossTotal;
  int64_t pktRetransTotal;
  int64_t pktRcvRetransTotal;
  int64_t pktSentACKTotal;
  int64_t pktRecvACKTotal;
  int64_t pktSentNAKTotal;
  int64_t pktRecvNAKTotal;
  int64_t usSndDurationTotal;
  int64_t pktSndDropTotal;
  int64_t pktRcvDropTotal;
  int64_t pktRcvUndecryptTotal;
  int64_t pktSndFilterExtraTotal;
  int64_t pktRcvFilterExtraTotal;
  int64_t pktRcvFilterSupplyTotal;
  int64_t pktRcvFilterLossTotal;
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
  int64_t pktSndLoss;
  int64_t pktRcvLoss;
  int64_t pktRetrans;
  int64_t pktRcvRetrans;
  int64_t pktSentACK;
  int64_t pktRecvACK;
  int64_t pktSentNAK;
  int64_t pktRecvNAK;
  int64_t pktSndFilterExtra;
  int64_t pktRcvFilterExtra;
  int64_t pktRcvFilterSupply;
  int64_t pktRcvFilterLoss;
  double mbpsSendRate;
  double mbpsRecvRate;
  int64_t usSndDuration;
  int64_t pktReorderDistance;
  int64_t pktRcvBelated;
  int64_t pktSndDrop;
  int64_t pktRcvDrop;

  static constexpr auto module = &atoms::ElixirSocketStats;

  static constexpr auto fields() {
    return std::make_tuple(
        std::make_tuple(&SocketStats::msTimeStamp, &atoms::msTimeStamp),
        std::make_tuple(&SocketStats::pktSentTotal, &atoms::pktSentTotal),
        std::make_tuple(&SocketStats::pktRecvTotal, &atoms::pktRecvTotal),
        std::make_tuple(&SocketStats::pktSentUniqueTotal,
                        &atoms::pktSentUniqueTotal),
        std::make_tuple(&SocketStats::pktRecvUniqueTotal,
                        &atoms::pktRecvUniqueTotal),
        std::make_tuple(&SocketStats::pktSndLossTotal, &atoms::pktSndLossTotal),
        std::make_tuple(&SocketStats::pktRcvLossTotal, &atoms::pktRcvLossTotal),
        std::make_tuple(&SocketStats::pktRetransTotal, &atoms::pktRetransTotal),
        std::make_tuple(&SocketStats::pktRcvRetransTotal,
                        &atoms::pktRcvRetransTotal),
        std::make_tuple(&SocketStats::pktSentACKTotal, &atoms::pktSentACKTotal),
        std::make_tuple(&SocketStats::pktRecvACKTotal, &atoms::pktRecvACKTotal),
        std::make_tuple(&SocketStats::pktSentNAKTotal, &atoms::pktSentNAKTotal),
        std::make_tuple(&SocketStats::pktRecvNAKTotal, &atoms::pktRecvNAKTotal),
        std::make_tuple(&SocketStats::usSndDurationTotal,
                        &atoms::usSndDurationTotal),
        std::make_tuple(&SocketStats::pktSndDropTotal, &atoms::pktSndDropTotal),
        std::make_tuple(&SocketStats::pktRcvDropTotal, &atoms::pktRcvDropTotal),
        std::make_tuple(&SocketStats::pktRcvUndecryptTotal,
                        &atoms::pktRcvUndecryptTotal),
        std::make_tuple(&SocketStats::pktSndFilterExtraTotal,
                        &atoms::pktSndFilterExtraTotal),
        std::make_tuple(&SocketStats::pktRcvFilterExtraTotal,
                        &atoms::pktRcvFilterExtraTotal),
        std::make_tuple(&SocketStats::pktRcvFilterSupplyTotal,
                        &atoms::pktRcvFilterSupplyTotal),
        std::make_tuple(&SocketStats::pktRcvFilterLossTotal,
                        &atoms::pktRcvFilterLossTotal),
        std::make_tuple(&SocketStats::byteSentTotal, &atoms::byteSentTotal),
        std::make_tuple(&SocketStats::byteRecvTotal, &atoms::byteRecvTotal),
        std::make_tuple(&SocketStats::byteSentUniqueTotal,
                        &atoms::byteSentUniqueTotal),
        std::make_tuple(&SocketStats::byteRecvUniqueTotal,
                        &atoms::byteRecvUniqueTotal),
        std::make_tuple(&SocketStats::byteRcvLossTotal,
                        &atoms::byteRcvLossTotal),
        std::make_tuple(&SocketStats::byteRetransTotal,
                        &atoms::byteRetransTotal),
        std::make_tuple(&SocketStats::byteSndDropTotal,
                        &atoms::byteSndDropTotal),
        std::make_tuple(&SocketStats::byteRcvDropTotal,
                        &atoms::byteRcvDropTotal),
        std::make_tuple(&SocketStats::byteRcvUndecryptTotal,
                        &atoms::byteRcvUndecryptTotal),
        std::make_tuple(&SocketStats::pktSent, &atoms::pktSent),
        std::make_tuple(&SocketStats::pktRecv, &atoms::pktRecv),
        std::make_tuple(&SocketStats::pktSentUnique, &atoms::pktSentUnique),
        std::make_tuple(&SocketStats::pktRecvUnique, &atoms::pktRecvUnique),
        std::make_tuple(&SocketStats::pktSndLoss, &atoms::pktSndLoss),
        std::make_tuple(&SocketStats::pktRcvLoss, &atoms::pktRcvLoss),
        std::make_tuple(&SocketStats::pktRetrans, &atoms::pktRetrans),
        std::make_tuple(&SocketStats::pktRcvRetrans, &atoms::pktRcvRetrans),
        std::make_tuple(&SocketStats::pktSentACK, &atoms::pktSentACK),
        std::make_tuple(&SocketStats::pktRecvACK, &atoms::pktRecvACK),
        std::make_tuple(&SocketStats::pktSentNAK, &atoms::pktSentNAK),
        std::make_tuple(&SocketStats::pktRecvNAK, &atoms::pktRecvNAK),
        std::make_tuple(&SocketStats::pktSndFilterExtra,
                        &atoms::pktSndFilterExtra),
        std::make_tuple(&SocketStats::pktRcvFilterExtra,
                        &atoms::pktRcvFilterExtra),
        std::make_tuple(&SocketStats::pktRcvFilterSupply,
                        &atoms::pktRcvFilterSupply),
        std::make_tuple(&SocketStats::pktRcvFilterLoss,
                        &atoms::pktRcvFilterLoss),
        std::make_tuple(&SocketStats::mbpsSendRate, &atoms::mbpsSendRate),
        std::make_tuple(&SocketStats::mbpsRecvRate, &atoms::mbpsRecvRate),
        std::make_tuple(&SocketStats::usSndDuration, &atoms::usSndDuration),
        std::make_tuple(&SocketStats::pktReorderDistance,
                        &atoms::pktReorderDistance),
        std::make_tuple(&SocketStats::pktRcvBelated, &atoms::pktRcvBelated),
        std::make_tuple(&SocketStats::pktSndDrop, &atoms::pktSndDrop),
        std::make_tuple(&SocketStats::pktRcvDrop, &atoms::pktRcvDrop));
  }
};

std::unique_ptr<SocketStats> readSocketStats(int socket, bool clean_intervals);
