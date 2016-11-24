
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

// http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// This file was initially generated by gen_to_start.go (add link), as a start
// of the Traffic Ops golang data model

package api

import (
	"encoding/json"
	"github.com/apache/incubator-trafficcontrol/traffic_ops/experimental/server/crconfig"
	_ "github.com/apache/incubator-trafficcontrol/traffic_ops/experimental/server/output_format" // needed for swagger
	"github.com/jmoiron/sqlx"
	"log"
)

// @Title snapshotCrconfig
// @Description create a snapshot for the given CDN
// @Accept  application/json
// @Param   name              path    string     false        "The CDN name"
// @Success 200 {object}    output_format.ApiWrapper
// @Resource /api/2.0
// @Router /api/2.0/snapshot/crconfig/{cdn} [get]
func snapshotCrconfig(cdn string, db *sqlx.DB) (interface{}, error) {
	resp, err := crconfig.GetCRConfig(cdn, db)
	if err != nil {
		return nil, err
	}

	jsonBytes, err := json.Marshal(resp)
	if err != nil {
		return nil, err
	}

	log.Println(cdn)
	log.Println(string(jsonBytes))
	result, err := db.Exec("INSERT INTO crconfig_snapshots (cdn, snapshot) VALUES ($1, $2);", cdn, string(jsonBytes))
	if err != nil {
		log.Println(err)
		return nil, err
	}

	return result, err
}
