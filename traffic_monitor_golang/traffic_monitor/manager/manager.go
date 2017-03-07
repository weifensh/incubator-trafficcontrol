package manager

/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import (
	"crypto/tls"
	"net/http"

	"github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/common/fetcher"
	"github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/common/handler"
	"github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/common/poller"
	"github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/traffic_monitor/cache"
	"github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/traffic_monitor/config"
	"github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/traffic_monitor/health"
	"github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/traffic_monitor/peer"
	"github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/traffic_monitor/threadsafe"
	todata "github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/traffic_monitor/trafficopsdata"
	towrap "github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/traffic_monitor/trafficopswrapper"
	"github.com/davecheney/gmx"
)

//
// Start starts the poller and handler goroutines
//
func Start(opsConfigFile string, cfg config.Config, staticAppData config.StaticAppData) {
	toSession := towrap.ITrafficOpsSession(towrap.NewTrafficOpsSessionThreadsafe(nil))
	counters := fetcher.Counters{
		Success: gmx.NewCounter("fetchSuccess"),
		Fail:    gmx.NewCounter("fetchFail"),
		Pending: gmx.NewGauge("fetchPending"),
	}

	sharedClient := &http.Client{
		Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}},
		Timeout:   cfg.HTTPTimeout,
	}

	localStates := peer.NewCRStatesThreadsafe() // this is the local state as discoverer by this traffic_monitor
	fetchCount := threadsafe.NewUint()          // note this is the number of individual caches fetched from, not the number of times all the caches were polled.
	healthIteration := threadsafe.NewUint()
	errorCount := threadsafe.NewUint()

	toData := todata.NewThreadsafe()

	cacheHealthHandler := cache.NewHandler()
	cacheHealthPoller := poller.NewHTTP(cfg.CacheHealthPollingInterval, true, sharedClient, counters, cacheHealthHandler, cfg.HTTPPollNoSleep)
	cacheStatHandler := cache.NewPrecomputeHandler(toData)
	cacheStatPoller := poller.NewHTTP(cfg.CacheStatPollingInterval, false, sharedClient, counters, cacheStatHandler, cfg.HTTPPollNoSleep)
	monitorConfigPoller := poller.NewMonitorConfig(cfg.MonitorConfigPollingInterval)
	peerHandler := peer.NewHandler()
	peerPoller := poller.NewHTTP(cfg.PeerPollingInterval, false, sharedClient, counters, peerHandler, cfg.HTTPPollNoSleep)

	go monitorConfigPoller.Poll()
	go cacheHealthPoller.Poll()
	go cacheStatPoller.Poll()
	go peerPoller.Poll()

	events := health.NewThreadsafeEvents(cfg.MaxEvents)

	cachesChanged := make(chan struct{})
	peerStates := peer.NewCRStatesPeersThreadsafe() // each peer's last state is saved in this map

	monitorConfig := StartMonitorConfigManager(
		monitorConfigPoller.ConfigChannel,
		localStates,
		peerStates,
		cacheStatPoller.ConfigChannel,
		cacheHealthPoller.ConfigChannel,
		peerPoller.ConfigChannel,
		cachesChanged,
		cfg,
		staticAppData,
	)

	combinedStates, combineStateFunc := StartStateCombiner(events, peerStates, localStates, toData)

	StartPeerManager(
		peerHandler.ResultChannel,
		peerStates,
		events,
		combineStateFunc,
	)

	statInfoHistory, statResultHistory, statMaxKbpses, _, lastKbpsStats, dsStats, unpolledCaches, localCacheStatus := StartStatHistoryManager(
		cacheStatHandler.ResultChan(),
		localStates,
		combinedStates,
		toData,
		cachesChanged,
		errorCount,
		cfg,
		monitorConfig,
		events,
		combineStateFunc,
	)

	lastHealthDurations, healthHistory := StartHealthResultManager(
		cacheHealthHandler.ResultChan(),
		toData,
		localStates,
		monitorConfig,
		combinedStates,
		fetchCount,
		errorCount,
		cfg,
		events,
		localCacheStatus,
	)

	StartOpsConfigManager(
		opsConfigFile,
		toSession,
		toData,
		[]chan<- handler.OpsConfig{monitorConfigPoller.OpsConfigChannel},
		[]chan<- towrap.ITrafficOpsSession{monitorConfigPoller.SessionChannel},
		localStates,
		peerStates,
		combinedStates,
		statInfoHistory,
		statResultHistory,
		statMaxKbpses,
		healthHistory,
		lastKbpsStats,
		dsStats,
		events,
		staticAppData,
		cacheHealthPoller.Config.Interval,
		lastHealthDurations,
		fetchCount,
		healthIteration,
		errorCount,
		localCacheStatus,
		unpolledCaches,
		monitorConfig,
		cfg,
	)

	healthTickListener(cacheHealthPoller.TickChan, healthIteration)
}

// healthTickListener listens for health ticks, and writes to the health iteration variable. Does not return.
func healthTickListener(cacheHealthTick <-chan uint64, healthIteration threadsafe.Uint) {
	for i := range cacheHealthTick {
		healthIteration.Set(i)
	}
}
