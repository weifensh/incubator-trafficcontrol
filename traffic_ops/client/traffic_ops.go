/*

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/

package client

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/http/cookiejar"
	"strings"
	"sync"
	"time"

	"golang.org/x/net/publicsuffix"
)

// Session ...
type Session struct {
	UserName     string
	Password     string
	URL          string
	Client       *http.Client
	cache        map[string]CacheEntry
	cacheMutex   *sync.RWMutex
	useCache     bool
	UserAgentStr string
}

func NewSession(user, password, url, userAgent string, client *http.Client, useCache bool) *Session {
	return &Session{
		UserName:     user,
		Password:     password,
		URL:          url,
		Client:       client,
		cache:        map[string]CacheEntry{},
		cacheMutex:   &sync.RWMutex{},
		useCache:     useCache,
		UserAgentStr: userAgent,
	}
}

const DefaultTimeout = time.Second * time.Duration(30)

// HTTPError is returned on Update Session failure.
type HTTPError struct {
	HTTPStatusCode int
	HTTPStatus     string
	URL            string
}

// Error implements the error interface for our customer error type.
func (e *HTTPError) Error() string {
	return fmt.Sprintf("%s[%d] - Error requesting Traffic Ops %s", e.HTTPStatus, e.HTTPStatusCode, e.URL)
}

// Result {"response":[{"level":"success","text":"Successfully logged in."}],"version":"1.1"}
type Result struct {
	Alerts []Alert
}

// Alert ...
type Alert struct {
	Level string `json:"level"`
	Text  string `json:"text"`
}

// CacheEntry ...
type CacheEntry struct {
	Entered int64
	Bytes   []byte
}

// Credentials contains Traffic Ops login credentials
type Credentials struct {
	Username string `json:"u"`
	Password string `json:"p"`
}

// TODO JvD
const tmPollingInterval = 60

// loginCreds gathers login credentials for Traffic Ops.
func loginCreds(toUser string, toPasswd string) ([]byte, error) {
	credentials := Credentials{
		Username: toUser,
		Password: toPasswd,
	}

	js, err := json.Marshal(credentials)
	if err != nil {
		err := fmt.Errorf("Error creating login json: %v", err)
		return nil, err
	}
	return js, nil
}

// Deprecated: Login is deprecated, use LoginWithAgent instead. The `Login` function with its present signature will be removed in the next version and replaced with `Login(toURL string, toUser string, toPasswd string, insecure bool, userAgent string)`. The `LoginWithAgent` function will be removed the version after that.
func Login(toURL string, toUser string, toPasswd string, insecure bool) (*Session, error) {
	return LoginWithAgent(toURL, toUser, toPasswd, insecure, "traffic-ops-client", false, DefaultTimeout) // TODO add UserAgent version
}

// Login to traffic_ops, the response should set the cookie for this session
// automatically. Start with
//     to := traffic_ops.Login("user", "passwd", true)
// subsequent calls like to.GetData("datadeliveryservice") will be authenticated.
func LoginWithAgent(toURL string, toUser string, toPasswd string, insecure bool, userAgent string, useCache bool, requestTimeout time.Duration) (*Session, error) {
	credentials, err := loginCreds(toUser, toPasswd)
	if err != nil {
		return nil, err
	}

	options := cookiejar.Options{
		PublicSuffixList: publicsuffix.List,
	}

	jar, err := cookiejar.New(&options)
	if err != nil {
		return nil, err
	}

	to := NewSession(toUser, toPasswd, toURL, userAgent, &http.Client{
		Timeout: requestTimeout,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: insecure},
		},
		Jar: jar,
	}, useCache)

	path := "/api/1.2/user/login"
	resp, err := to.request("POST", path, credentials)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result Result
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	success := false
	for _, alert := range result.Alerts {
		if alert.Level == "success" && alert.Text == "Successfully logged in." {
			success = true
			break
		}
	}

	if !success {
		err := fmt.Errorf("Login failed, result string: %+v", result)
		return nil, err
	}

	return to, nil
}

// request performs the actual HTTP request to Traffic Ops
func (to *Session) request(method, path string, body []byte) (*http.Response, error) {
	url := fmt.Sprintf("%s%s", to.URL, path)

	var req *http.Request
	var err error

	if body != nil {
		req, err = http.NewRequest(method, url, bytes.NewBuffer(body))
		if err != nil {
			return nil, err
		}
		req.Header.Set("Content-Type", "application/json")
	} else {
		req, err = http.NewRequest(method, url, nil)
		if err != nil {
			return nil, err
		}
	}

	req.Header.Set("User-Agent", to.UserAgentStr)
	resp, err := to.Client.Do(req)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		e := HTTPError{
			HTTPStatus:     resp.Status,
			HTTPStatusCode: resp.StatusCode,
			URL:            url,
		}
		return nil, &e
	}

	return resp, nil
}

type CacheHitStatus string

const CacheHitStatusHit = CacheHitStatus("hit")
const CacheHitStatusExpired = CacheHitStatus("expired")
const CacheHitStatusMiss = CacheHitStatus("miss")
const CacheHitStatusInvalid = CacheHitStatus("")

func (s CacheHitStatus) String() string {
	return string(s)
}

func StringToCacheHitStatus(s string) CacheHitStatus {
	s = strings.ToLower(s)
	switch s {
	case "hit":
		return CacheHitStatusHit
	case "expired":
		return CacheHitStatusExpired
	case "miss":
		return CacheHitStatusMiss
	default:
		return CacheHitStatusInvalid
	}
}

// setCache Sets the given cache key and value. This is threadsafe for multiple goroutines.
func (to *Session) setCache(path string, entry CacheEntry) {
	if !to.useCache {
		return
	}
	to.cacheMutex.Lock()
	defer to.cacheMutex.Unlock()
	to.cache[path] = entry
}

// getCache gets the cache value at the given key, or false if it doesn't exist. This is threadsafe for multiple goroutines.
func (to *Session) getCache(path string) (CacheEntry, bool) {
	to.cacheMutex.RLock()
	defer to.cacheMutex.RUnlock()
	cacheEntry, ok := to.cache[path]
	return cacheEntry, ok
}

//if cacheEntry, ok := to.Cache[path]; ok {

// getBytesWithTTL - get the path, and cache in the session
// return from cache is found and the ttl isn't expired, otherwise get it and
// store it in cache
func (to *Session) getBytesWithTTL(path string, ttl int64) ([]byte, CacheHitStatus, error) {
	var body []byte
	var err error
	var cacheHitStatus CacheHitStatus
	getFresh := false
	if cacheEntry, ok := to.getCache(path); ok {
		if cacheEntry.Entered > time.Now().Unix()-ttl {
			cacheHitStatus = CacheHitStatusHit
			body = cacheEntry.Bytes
		} else {
			cacheHitStatus = CacheHitStatusExpired
			getFresh = true
		}
	} else {
		cacheHitStatus = CacheHitStatusMiss
		getFresh = true
	}

	if getFresh {
		body, err = to.getBytes(path)
		if err != nil {
			return nil, CacheHitStatusInvalid, err
		}

		newEntry := CacheEntry{
			Entered: time.Now().Unix(),
			Bytes:   body,
		}
		to.setCache(path, newEntry)
	}

	return body, cacheHitStatus, nil
}

// GetBytes - get []bytes array for a certain path on the to session.
// returns the raw body
func (to *Session) getBytes(path string) ([]byte, error) {
	resp, err := to.request("GET", path, nil)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	return body, nil
}
