{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Cardano.Tracer.Types
  ( AcceptedMetrics
  , AcceptedNodeInfo
  , ConnectedNodesIds
  , Metrics
  , NodeId (..)
  , NodeIds
  , connIdToNodeId
  , initAcceptedMetrics
  , initAcceptedNodeInfo
  , initConnectedNodesIds
  , prepareAcceptedMetrics
  ) where

import           Control.Concurrent.STM (atomically)
import           Control.Concurrent.STM.TVar (TVar, modifyTVar', newTVarIO, readTVarIO)
import           Control.Monad (unless)
import           Data.Hashable (Hashable)
import           Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
import           Data.Text (Text, replace, pack)
import           GHC.Generics (Generic)
import qualified System.Metrics as EKG

import           Ouroboros.Network.Socket (ConnectionId (..))

import           Trace.Forward.Protocol.Type (NodeInfo)

import           System.Metrics.Store.Acceptor (MetricsLocalStore, emptyMetricsLocalStore)

-- | Unique identifier of the node, based on 'remoteAddress' from 'ConnectionId'.
newtype NodeId = NodeId Text
  deriving (Eq, Generic, Hashable, Ord, Show)

type NodeIds = [NodeId]

connIdToNodeId :: Show addr => ConnectionId addr -> NodeId
connIdToNodeId ConnectionId{remoteAddress} = NodeId preparedAddress
 where
  -- We have to remove "wrong" symbols from 'NodeId',
  -- to make it appropriate for the name of the subdirectory.
  preparedAddress =
      replace " "  "-"
    . replace "\"" ""
    . replace "/"  "-"
    . pack
    $ show remoteAddress

-- | We have to create EKG.Store and MetricsLocalStore
--   to keep the metrics accepted from the node.
type Metrics = (EKG.Store, TVar MetricsLocalStore)

type AcceptedMetrics = TVar (HashMap NodeId Metrics)

type AcceptedNodeInfo = TVar (HashMap NodeId NodeInfo)

type ConnectedNodesIds = TVar NodeIds

initAcceptedMetrics :: IO AcceptedMetrics
initAcceptedMetrics = newTVarIO HM.empty

initAcceptedNodeInfo :: IO AcceptedNodeInfo
initAcceptedNodeInfo = newTVarIO HM.empty

initConnectedNodesIds :: IO ConnectedNodesIds
initConnectedNodesIds = newTVarIO []

prepareAcceptedMetrics
  :: NodeId
  -> AcceptedMetrics
  -> IO ()
prepareAcceptedMetrics nodeId acceptedMetrics = do
  metrics <- readTVarIO acceptedMetrics
  unless (nodeId `HM.member` metrics) $ do
    storesForNewNode <-
      (,) <$> EKG.newStore
          <*> newTVarIO emptyMetricsLocalStore
    atomically $ modifyTVar' acceptedMetrics $ HM.insert nodeId storesForNewNode
