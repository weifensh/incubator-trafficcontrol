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

var AuthService = function($http, $state, $location, $q, $state, httpService, userModel, messageModel, ENV) {

    this.login = function(username, password) {
        userModel.resetUser();
        return httpService.post(ENV.api['root'] + 'user/login', { u: username, p: password })
            .then(
                function(result) {
                    var redirect = decodeURIComponent($location.search().redirect);
                    if (redirect !== 'undefined') {
                        $location.search('redirect', null); // remove the redirect query param
                        $location.url(redirect);
                    } else {
                        $location.url('/monitor/dashboards/one');
                    }
                },
                function(fault) {
                    // do nothing
                }
            );
    };

    this.tokenLogin = function(token) {
        userModel.resetUser();
        return httpService.post(ENV.api['root'] + 'user/login/token', { t: token });
    };

    this.logout = function() {
        userModel.resetUser();
        httpService.post(ENV.api['root'] + 'user/logout').
            then(
                function(result) {
                    if ($state.current.name == 'trafficOps.public.login') {
                        messageModel.setMessages(result.alerts, false);
                    } else {
                        messageModel.setMessages(result.alerts, true);
                        $state.go('trafficOps.public.login');
                    }
                    return result;
                }
        );
    };

    this.resetPassword = function(email) {
        // Todo: api endpoint not implemented yet
    };

};

AuthService.$inject = ['$http', '$state', '$location', '$q', '$state', 'httpService', 'userModel', 'messageModel', 'ENV'];
module.exports = AuthService;
