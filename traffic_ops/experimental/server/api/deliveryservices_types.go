
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
	_ "github.com/apache/incubator-trafficcontrol/traffic_ops/experimental/server/output_format" // needed for swagger
	"github.com/jmoiron/sqlx"
	"log"
	"time"
)

type DeliveryservicesTypes struct {
	Name        string                     `db:"name" json:"name"`
	Description string                     `db:"description" json:"description"`
	CreatedAt   time.Time                  `db:"created_at" json:"createdAt"`
	Links       DeliveryservicesTypesLinks `json:"_links" db:-`
}

type DeliveryservicesTypesLinks struct {
	Self string `db:"self" json:"_self"`
}

type DeliveryservicesTypesLink struct {
	ID  string `db:"deliveryservices_type" json:"name"`
	Ref string `db:"deliveryservices_types_name_ref" json:"_ref"`
}

// @Title getDeliveryservicesTypesById
// @Description retrieves the deliveryservices_types information for a certain id
// @Accept  application/json
// @Param   id              path    int     false        "The row id"
// @Success 200 {array}    DeliveryservicesTypes
// @Resource /api/2.0
// @Router /api/2.0/deliveryservices_types/{id} [get]
func getDeliveryservicesType(name string, db *sqlx.DB) (interface{}, error) {
	ret := []DeliveryservicesTypes{}
	arg := DeliveryservicesTypes{}
	arg.Name = name
	queryStr := "select *, concat('" + API_PATH + "deliveryservices_types/', name) as self"
	queryStr += " from deliveryservices_types WHERE name=:name"
	nstmt, err := db.PrepareNamed(queryStr)
	err = nstmt.Select(&ret, arg)
	if err != nil {
		log.Println(err)
		return nil, err
	}
	nstmt.Close()
	return ret, nil
}

// @Title getDeliveryservicesTypess
// @Description retrieves the deliveryservices_types
// @Accept  application/json
// @Success 200 {array}    DeliveryservicesTypes
// @Resource /api/2.0
// @Router /api/2.0/deliveryservices_types [get]
func getDeliveryservicesTypes(db *sqlx.DB) (interface{}, error) {
	ret := []DeliveryservicesTypes{}
	queryStr := "select *, concat('" + API_PATH + "deliveryservices_types/', name) as self"
	queryStr += " from deliveryservices_types"
	err := db.Select(&ret, queryStr)
	if err != nil {
		log.Println(err)
		return nil, err
	}
	return ret, nil
}

// @Title postDeliveryservicesTypes
// @Description enter a new deliveryservices_types
// @Accept  application/json
// @Param                 Body body     DeliveryservicesTypes   true "DeliveryservicesTypes object that should be added to the table"
// @Success 200 {object}    output_format.ApiWrapper
// @Resource /api/2.0
// @Router /api/2.0/deliveryservices_types [post]
func postDeliveryservicesType(payload []byte, db *sqlx.DB) (interface{}, error) {
	var v DeliveryservicesTypes
	err := json.Unmarshal(payload, &v)
	if err != nil {
		log.Println(err)
		return nil, err
	}
	sqlString := "INSERT INTO deliveryservices_types("
	sqlString += "name"
	sqlString += ",description"
	sqlString += ",created_at"
	sqlString += ") VALUES ("
	sqlString += ":name"
	sqlString += ",:description"
	sqlString += ",:created_at"
	sqlString += ")"
	result, err := db.NamedExec(sqlString, v)
	if err != nil {
		log.Println(err)
		return nil, err
	}
	return result, err
}

// @Title putDeliveryservicesTypes
// @Description modify an existing deliveryservices_typesentry
// @Accept  application/json
// @Param   id              path    int     true        "The row id"
// @Param                 Body body     DeliveryservicesTypes   true "DeliveryservicesTypes object that should be added to the table"
// @Success 200 {object}    output_format.ApiWrapper
// @Resource /api/2.0
// @Router /api/2.0/deliveryservices_types/{id}  [put]
func putDeliveryservicesType(name string, payload []byte, db *sqlx.DB) (interface{}, error) {
	var arg DeliveryservicesTypes
	err := json.Unmarshal(payload, &arg)
	arg.Name = name
	if err != nil {
		log.Println(err)
		return nil, err
	}
	sqlString := "UPDATE deliveryservices_types SET "
	sqlString += "name = :name"
	sqlString += ",description = :description"
	sqlString += ",created_at = :created_at"
	sqlString += " WHERE name=:name"
	result, err := db.NamedExec(sqlString, arg)
	if err != nil {
		log.Println(err)
		return nil, err
	}
	return result, err
}

// @Title delDeliveryservicesTypesById
// @Description deletes deliveryservices_types information for a certain id
// @Accept  application/json
// @Param   id              path    int     false        "The row id"
// @Success 200 {array}    DeliveryservicesTypes
// @Resource /api/2.0
// @Router /api/2.0/deliveryservices_types/{id} [delete]
func delDeliveryservicesType(name string, db *sqlx.DB) (interface{}, error) {
	arg := DeliveryservicesTypes{}
	arg.Name = name
	result, err := db.NamedExec("DELETE FROM deliveryservices_types WHERE name=:name", arg)
	if err != nil {
		log.Println(err)
		return nil, err
	}
	return result, err
}
