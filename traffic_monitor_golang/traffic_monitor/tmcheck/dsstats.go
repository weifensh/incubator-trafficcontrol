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

package tmcheck

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/traffic_monitor/crconfig"
	dsdata "github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/traffic_monitor/deliveryservicedata"
	"github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/traffic_monitor/enum"
	to "github.com/apache/incubator-trafficcontrol/traffic_ops/client"
)

// ValidateDSStates validates that all Delivery Services in the CRConfig exist in given Traffic Monitor's DSStats.
// Existence in DSStats is useful to verify, because "Available: false" in CRStates
func ValidateDSStats(tmURI string, toClient *to.Session) error {
	cdn, err := GetCDN(tmURI)
	if err != nil {
		return fmt.Errorf("getting CDN from Traffic Monitor: %v", err)
	}
	return ValidateDSStatsWithCDN(tmURI, cdn, toClient)
}

// ValidateOfflineStatesWithCDN validates per ValidateOfflineStates, but saves an additional query if the Traffic Monitor's CDN is known.
func ValidateDSStatsWithCDN(tmURI string, tmCDN string, toClient *to.Session) error {
	crConfigBytes, err := toClient.CRConfigRaw(tmCDN)
	if err != nil {
		return fmt.Errorf("getting CRConfig: %v", err)
	}

	crConfig := crconfig.CRConfig{}
	if err := json.Unmarshal(crConfigBytes, &crConfig); err != nil {
		return fmt.Errorf("unmarshalling CRConfig JSON: %v", err)
	}

	return ValidateDSStatsWithCRConfig(tmURI, &crConfig, toClient)
}

// ValidateOfflineStatesWithCRConfig validates per ValidateOfflineStates, but saves querying the CRconfig if it's already fetched.
func ValidateDSStatsWithCRConfig(tmURI string, crConfig *crconfig.CRConfig, toClient *to.Session) error {
	dsStats, err := GetDSStats(tmURI + TrafficMonitorDSStatsPath)
	if err != nil {
		return fmt.Errorf("getting DSStats: %v", err)
	}

	return ValidateDSStatsData(dsStats, crConfig)
}

func hasCaches(dsName string, crconfig *crconfig.CRConfig) bool {
	for _, server := range crconfig.ContentServers {
		if _, ok := server.DeliveryServices[dsName]; ok {
			return true
		}
	}
	return false
}

// ValidateDSStatsData validates that all delivery services in the given CRConfig with caches assigned exist in the given DSStats.
func ValidateDSStatsData(dsStats *dsdata.StatsOld, crconfig *crconfig.CRConfig) error {
	for dsName, _ := range crconfig.DeliveryServices {
		if !hasCaches(dsName, crconfig) {
			continue
		}
		if _, ok := dsStats.DeliveryService[enum.DeliveryServiceName(dsName)]; !ok {
			return fmt.Errorf("Delivery Service %v in CRConfig but not DSStats", dsName)
		}
	}
	return nil
}

// DSStatsValidator is designed to be run as a goroutine, and does not return. It continously validates every `interval`, and calls `onErr` on failure, `onResumeSuccess` when a failure ceases, and `onCheck` on every poll.
func DSStatsValidator(
	tmURI string,
	toClient *to.Session,
	interval time.Duration,
	grace time.Duration,
	onErr func(error),
	onResumeSuccess func(),
	onCheck func(error),
) {
	Validator(tmURI, toClient, interval, grace, onErr, onResumeSuccess, onCheck, ValidateDSStats)
}

// AllMonitorsDSStatsValidator is designed to be run as a goroutine, and does not return. It continously validates every `interval`, and calls `onErr` on failure, `onResumeSuccess` when a failure ceases, and `onCheck` on every poll. Note the error passed to `onErr` may be a general validation error not associated with any monitor, in which case the passed `enum.TrafficMonitorName` will be empty.
func AllMonitorsDSStatsValidator(
	toClient *to.Session,
	interval time.Duration,
	includeOffline bool,
	grace time.Duration,
	onErr func(enum.TrafficMonitorName, error),
	onResumeSuccess func(enum.TrafficMonitorName),
	onCheck func(enum.TrafficMonitorName, error),
) {
	AllValidator(toClient, interval, includeOffline, grace, onErr, onResumeSuccess, onCheck, ValidateAllMonitorsDSStats)
}

// ValidateAllMonitorDSStats validates, for all monitors in the given Traffic Ops, DSStats contains all Delivery Services in the CRConfig.
func ValidateAllMonitorsDSStats(toClient *to.Session, includeOffline bool) (map[enum.TrafficMonitorName]error, error) {
	servers, err := GetMonitors(toClient, includeOffline)
	if err != nil {
		return nil, err
	}

	crConfigs := GetCRConfigs(GetCDNs(servers), toClient)

	errs := map[enum.TrafficMonitorName]error{}
	for _, server := range servers {
		crConfig := crConfigs[enum.CDNName(server.CDNName)]
		if err := crConfig.Err; err != nil {
			errs[enum.TrafficMonitorName(server.HostName)] = fmt.Errorf("getting CRConfig: %v", err)
			continue
		}

		uri := fmt.Sprintf("http://%s.%s", server.HostName, server.DomainName)
		errs[enum.TrafficMonitorName(server.HostName)] = ValidateDSStatsWithCRConfig(uri, crConfig.CRConfig, toClient)
	}
	return errs, nil
}
