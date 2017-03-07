package trafficopsdata

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
	"encoding/json"
	"fmt"
	"github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/traffic_monitor/enum"
	towrap "github.com/apache/incubator-trafficcontrol/traffic_monitor_golang/traffic_monitor/trafficopswrapper"
	"regexp"
	"strings"
	"sync"
)

// Regexes maps Delivery Service Regular Expressions to delivery services.
// For performance, we categorize Regular Expressions into 3 categories:
// 1. Direct string matches, with no regular expression matching characters
// 2. .*\.foo\..* expressions, where foo is a direct string match with no regular expression matching characters
// 3. Everything else
// This allows us to do a cheap match on 1 and 2, and only regex match the uncommon case.
type Regexes struct {
	DirectMatches                      map[string]enum.DeliveryServiceName
	DotStartSlashDotFooSlashDotDotStar map[string]enum.DeliveryServiceName
	RegexMatch                         map[*regexp.Regexp]enum.DeliveryServiceName
}

// DeliveryService returns the delivery service which matches the given fqdn, or false.
func (d Regexes) DeliveryService(domain, subdomain, subsubdomain string) (enum.DeliveryServiceName, bool) {
	if ds, ok := d.DotStartSlashDotFooSlashDotDotStar[subdomain]; ok {
		return ds, true
	}
	fqdn := fmt.Sprintf("%s.%s.%s", subsubdomain, subdomain, domain)
	if ds, ok := d.DirectMatches[fqdn]; ok {
		return ds, true
	}
	for regex, ds := range d.RegexMatch {
		if regex.MatchString(fqdn) {
			return ds, true
		}
	}
	return "", false
}

// NewRegexes constructs a new Regexes object, initializing internal pointer members.
func NewRegexes() Regexes {
	return Regexes{DirectMatches: map[string]enum.DeliveryServiceName{}, DotStartSlashDotFooSlashDotDotStar: map[string]enum.DeliveryServiceName{}, RegexMatch: map[*regexp.Regexp]enum.DeliveryServiceName{}}
}

// TOData holds CDN data fetched from Traffic Ops.
type TOData struct {
	DeliveryServiceServers map[enum.DeliveryServiceName][]enum.CacheName
	ServerDeliveryServices map[enum.CacheName][]enum.DeliveryServiceName
	ServerTypes            map[enum.CacheName]enum.CacheType
	DeliveryServiceTypes   map[enum.DeliveryServiceName]enum.DSType
	DeliveryServiceRegexes Regexes
	ServerCachegroups      map[enum.CacheName]enum.CacheGroupName
}

// New returns a new empty TOData object, initializing pointer members.
func New() *TOData {
	return &TOData{
		DeliveryServiceServers: map[enum.DeliveryServiceName][]enum.CacheName{},
		ServerDeliveryServices: map[enum.CacheName][]enum.DeliveryServiceName{},
		ServerTypes:            map[enum.CacheName]enum.CacheType{},
		DeliveryServiceTypes:   map[enum.DeliveryServiceName]enum.DSType{},
		DeliveryServiceRegexes: NewRegexes(),
		ServerCachegroups:      map[enum.CacheName]enum.CacheGroupName{},
	}
}

// TODataThreadsafe provides safe access for multiple goroutine writers and one goroutine reader, to the encapsulated TOData object.
// This could be made lock-free, if the performance was necessary
type TODataThreadsafe struct {
	toData *TOData
	m      *sync.RWMutex
}

// NewThreadsafe returns a new TOData object, wrapped to be safe for multiple goroutine readers and a single writer.
func NewThreadsafe() TODataThreadsafe {
	return TODataThreadsafe{m: &sync.RWMutex{}, toData: New()}
}

// Get returns the current TOData. Callers MUST NOT modify returned data. Mutation IS NOT threadsafe
// If callers need to modify, a new GetMutable() should be added which copies.
func (d TODataThreadsafe) Get() TOData {
	d.m.RLock()
	defer d.m.RUnlock()
	return *d.toData
}

func (d TODataThreadsafe) set(newTOData TOData) {
	d.m.Lock()
	*d.toData = newTOData
	d.m.Unlock()
}

// CRConfig is the CrConfig data needed by TOData. Note this is not all data in the CRConfig.
// TODO change strings to type?
type CRConfig struct {
	ContentServers map[enum.CacheName]struct {
		DeliveryServices map[enum.DeliveryServiceName][]string `json:"deliveryServices"`
		CacheGroup       string                                `json:"cacheGroup"`
		Type             string                                `json:"type"`
	} `json:"contentServers"`
	DeliveryServices map[enum.DeliveryServiceName]struct {
		Matchsets []struct {
			Protocol  string `json:"protocol"`
			MatchList []struct {
				Regex string `json:"regex"`
			} `json:"matchlist"`
		} `json:"matchsets"`
	} `json:"deliveryServices"`
}

// Fetch gets the CRConfig from Traffic Ops, creates the TOData maps, and atomically sets the TOData.
// TODO since the session is threadsafe, each TOData get func below could be put in a goroutine, if performance mattered
func (d TODataThreadsafe) Fetch(to towrap.ITrafficOpsSession, cdn string) error {
	newTOData := TOData{}

	crConfigBytes, err := to.CRConfigRaw(cdn)
	if err != nil {
		return fmt.Errorf("Error getting CRconfig from Traffic Ops: %v", err)
	}
	var crConfig CRConfig
	err = json.Unmarshal(crConfigBytes, &crConfig)
	if err != nil {
		return fmt.Errorf("Error unmarshalling CRconfig: %v", err)
	}

	newTOData.DeliveryServiceServers, newTOData.ServerDeliveryServices, err = getDeliveryServiceServers(crConfig)
	if err != nil {
		return err
	}

	newTOData.DeliveryServiceTypes, err = getDeliveryServiceTypes(crConfig)
	if err != nil {
		return fmt.Errorf("Error getting delivery service types from Traffic Ops: %v\n", err)
	}

	newTOData.DeliveryServiceRegexes, err = getDeliveryServiceRegexes(crConfig)
	if err != nil {
		return fmt.Errorf("Error getting delivery service regexes from Traffic Ops: %v\n", err)
	}

	newTOData.ServerCachegroups, err = getServerCachegroups(crConfig)
	if err != nil {
		return fmt.Errorf("Error getting server cachegroups from Traffic Ops: %v\n", err)
	}

	newTOData.ServerTypes, err = getServerTypes(crConfig)
	if err != nil {
		return fmt.Errorf("Error getting server types from Traffic Ops: %v\n", err)
	}

	d.set(newTOData)
	return nil
}

// getDeliveryServiceServers gets the servers on each delivery services, for the given CDN, from Traffic Ops.
func getDeliveryServiceServers(crc CRConfig) (map[enum.DeliveryServiceName][]enum.CacheName, map[enum.CacheName][]enum.DeliveryServiceName, error) {
	dsServers := map[enum.DeliveryServiceName][]enum.CacheName{}
	serverDses := map[enum.CacheName][]enum.DeliveryServiceName{}

	for serverName, serverData := range crc.ContentServers {
		for deliveryServiceName := range serverData.DeliveryServices {
			dsServers[deliveryServiceName] = append(dsServers[deliveryServiceName], serverName)
			serverDses[serverName] = append(serverDses[serverName], deliveryServiceName)
		}
	}
	return dsServers, serverDses, nil
}

// getDeliveryServiceRegexes gets the regexes of each delivery service, for the given CDN, from Traffic Ops.
// Returns a map[deliveryService][]regex.
func getDeliveryServiceRegexes(crc CRConfig) (Regexes, error) {
	dsRegexes := map[enum.DeliveryServiceName][]string{}

	for dsName, dsData := range crc.DeliveryServices {
		if len(dsData.Matchsets) < 1 {
			return Regexes{}, fmt.Errorf("CRConfig missing regex for '%s'", dsName)
		}
		for _, matchset := range dsData.Matchsets {
			if len(matchset.MatchList) < 1 {
				return Regexes{}, fmt.Errorf("CRConfig missing Regex for '%s'", dsName)
			}
			dsRegexes[dsName] = append(dsRegexes[dsName], matchset.MatchList[0].Regex)
		}
	}

	return createRegexes(dsRegexes)
}

// TODO precompute, move to TOData; call when we get new delivery services, instead of every time we create new stats
func createRegexes(dsToRegex map[enum.DeliveryServiceName][]string) (Regexes, error) {
	dsRegexes := Regexes{
		DirectMatches:                      map[string]enum.DeliveryServiceName{},
		DotStartSlashDotFooSlashDotDotStar: map[string]enum.DeliveryServiceName{},
		RegexMatch:                         map[*regexp.Regexp]enum.DeliveryServiceName{},
	}

	for ds, regexStrs := range dsToRegex {
		for _, regexStr := range regexStrs {
			prefix := `.*\.`
			suffix := `\..*`
			if strings.HasPrefix(regexStr, prefix) && strings.HasSuffix(regexStr, suffix) {
				matchStr := regexStr[len(prefix) : len(regexStr)-len(suffix)]
				if otherDs, ok := dsRegexes.DotStartSlashDotFooSlashDotDotStar[matchStr]; ok {
					return dsRegexes, fmt.Errorf("duplicate regex %s (%s) in %s and %s", regexStr, matchStr, ds, otherDs)
				}
				dsRegexes.DotStartSlashDotFooSlashDotDotStar[matchStr] = ds
				continue
			}
			if !strings.ContainsAny(regexStr, `[]^\:{}()|?+*,=%@<>!'`) {
				if otherDs, ok := dsRegexes.DirectMatches[regexStr]; ok {
					return dsRegexes, fmt.Errorf("duplicate Regex %s in %s and %s", regexStr, ds, otherDs)
				}
				dsRegexes.DirectMatches[regexStr] = ds
				continue
			}
			// TODO warn? regex matches are unusual
			r, err := regexp.Compile(regexStr)
			if err != nil {
				return dsRegexes, fmt.Errorf("regex %s failed to compile: %v", regexStr, err)
			}
			dsRegexes.RegexMatch[r] = ds
		}
	}
	return dsRegexes, nil
}

// getServerCachegroups gets the cachegroup of each ATS Edge+Mid Cache server, for the given CDN, from Traffic Ops.
// Returns a map[server]cachegroup.
func getServerCachegroups(crc CRConfig) (map[enum.CacheName]enum.CacheGroupName, error) {
	serverCachegroups := map[enum.CacheName]enum.CacheGroupName{}

	for server, serverData := range crc.ContentServers {
		serverCachegroups[server] = enum.CacheGroupName(serverData.CacheGroup)
	}
	return serverCachegroups, nil
}

// getServerTypes gets the cache type of each ATS Edge+Mid Cache server, for the given CDN, from Traffic Ops.
func getServerTypes(crc CRConfig) (map[enum.CacheName]enum.CacheType, error) {
	serverTypes := map[enum.CacheName]enum.CacheType{}

	for server, serverData := range crc.ContentServers {
		t := enum.CacheTypeFromString(serverData.Type)
		if t == enum.CacheTypeInvalid {
			return nil, fmt.Errorf("getServerTypes CRConfig unknown type for '%s': '%s'", server, serverData.Type)
		}
		serverTypes[server] = t
	}
	return serverTypes, nil
}

func getDeliveryServiceTypes(crc CRConfig) (map[enum.DeliveryServiceName]enum.DSType, error) {
	dsTypes := map[enum.DeliveryServiceName]enum.DSType{}

	for dsName, dsData := range crc.DeliveryServices {
		if len(dsData.Matchsets) < 1 {
			return nil, fmt.Errorf("CRConfig missing protocol for '%s'", dsName)
		}
		dsTypeStr := dsData.Matchsets[0].Protocol
		dsType := enum.DSTypeFromString(dsTypeStr)
		if dsType == enum.DSTypeInvalid {
			return nil, fmt.Errorf("CRConfig unknowng protocol for '%s': '%s'", dsName, dsTypeStr)
		}
		dsTypes[dsName] = dsType
	}
	return dsTypes, nil
}
