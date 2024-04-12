defmodule ExLibSRT do
  @moduledoc """
  Bindings to [libsrt](https://github.com/Haivision/srt) library.

  Available modules:
  * `ExLibSRT.Client` - SRT client implementation
  * `ExLibSRT.Server` - SRT server implementation
  """

  defmodule SocketStats do
    @moduledoc """
    Structure representing socket statistics.

    For meaning of the attributes please refer to the [documentation](https://github.com/Haivision/srt).
    """
    @type t :: %__MODULE__{
            msTimeStamp: integer(),
            pktSentTotal: integer(),
            pktRecvTotal: integer(),
            pktSentUniqueTotal: integer(),
            pktRecvUniqueTotal: integer(),
            pktSndLossTotal: integer(),
            pktRcvLossTotal: integer(),
            pktRetransTotal: integer(),
            pktRcvRetransTotal: integer(),
            pktSentACKTotal: integer(),
            pktRecvACKTotal: integer(),
            pktSentNAKTotal: integer(),
            pktRecvNAKTotal: integer(),
            usSndDurationTotal: integer(),
            pktSndDropTotal: integer(),
            pktRcvDropTotal: integer(),
            pktRcvUndecryptTotal: integer(),
            pktSndFilterExtraTotal: integer(),
            pktRcvFilterExtraTotal: integer(),
            pktRcvFilterSupplyTotal: integer(),
            pktRcvFilterLossTotal: integer(),
            byteSentTotal: non_neg_integer(),
            byteRecvTotal: non_neg_integer(),
            byteSentUniqueTotal: non_neg_integer(),
            byteRecvUniqueTotal: non_neg_integer(),
            byteRcvLossTotal: non_neg_integer(),
            byteRetransTotal: non_neg_integer(),
            byteSndDropTotal: non_neg_integer(),
            byteRcvDropTotal: non_neg_integer(),
            byteRcvUndecryptTotal: non_neg_integer(),
            pktSent: integer(),
            pktRecv: integer(),
            pktSentUnique: integer(),
            pktRecvUnique: integer(),
            pktSndLoss: integer(),
            pktRcvLoss: integer(),
            pktRetrans: integer(),
            pktRcvRetrans: integer(),
            pktSentACK: integer(),
            pktRecvACK: integer(),
            pktSentNAK: integer(),
            pktRecvNAK: integer(),
            pktSndFilterExtra: integer(),
            pktRcvFilterExtra: integer(),
            pktRcvFilterSupply: integer(),
            pktRcvFilterLoss: integer(),
            mbpsSendRate: float(),
            mbpsRecvRate: float(),
            usSndDuration: integer(),
            pktReorderDistance: integer(),
            pktRcvBelated: integer(),
            pktSndDrop: integer(),
            pktRcvDrop: integer()
          }
    @enforce_keys [
      :msTimeStamp,
      :pktSentTotal,
      :pktRecvTotal,
      :pktSentUniqueTotal,
      :pktRecvUniqueTotal,
      :pktSndLossTotal,
      :pktRcvLossTotal,
      :pktRetransTotal,
      :pktRcvRetransTotal,
      :pktSentACKTotal,
      :pktRecvACKTotal,
      :pktSentNAKTotal,
      :pktRecvNAKTotal,
      :usSndDurationTotal,
      :pktSndDropTotal,
      :pktRcvDropTotal,
      :pktRcvUndecryptTotal,
      :pktSndFilterExtraTotal,
      :pktRcvFilterExtraTotal,
      :pktRcvFilterSupplyTotal,
      :pktRcvFilterLossTotal,
      :byteSentTotal,
      :byteRecvTotal,
      :byteSentUniqueTotal,
      :byteRecvUniqueTotal,
      :byteRcvLossTotal,
      :byteRetransTotal,
      :byteSndDropTotal,
      :byteRcvDropTotal,
      :byteRcvUndecryptTotal,
      :pktSent,
      :pktRecv,
      :pktSentUnique,
      :pktRecvUnique,
      :pktSndLoss,
      :pktRcvLoss,
      :pktRetrans,
      :pktRcvRetrans,
      :pktSentACK,
      :pktRecvACK,
      :pktSentNAK,
      :pktRecvNAK,
      :pktSndFilterExtra,
      :pktRcvFilterExtra,
      :pktRcvFilterSupply,
      :pktRcvFilterLoss,
      :mbpsSendRate,
      :mbpsRecvRate,
      :usSndDuration,
      :pktReorderDistance,
      :pktRcvBelated,
      :pktSndDrop,
      :pktRcvDrop
    ]

    defstruct @enforce_keys
  end
end
