package Fixtures::Integration::DeliveryserviceRegex;

# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
# 
#   http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.


# Do not edit! Generated code.
# See https://github.com/Comcast/traffic_control/wiki/The%20Kabletown%20example

use Moose;
extends 'DBIx::Class::EasyFixture';
use namespace::autoclean;

my %definition_for = (
'0' => { new => 'DeliveryserviceRegex', => using => { regex => '1', set_number => '0', deliveryservice => '1', }, }, 
'1' => { new => 'DeliveryserviceRegex', => using => { deliveryservice => '2', regex => '2', set_number => '0', }, }, 
'2' => { new => 'DeliveryserviceRegex', => using => { set_number => '0', deliveryservice => '3', regex => '3', }, }, 
'3' => { new => 'DeliveryserviceRegex', => using => { deliveryservice => '4', regex => '4', set_number => '0', }, }, 
'4' => { new => 'DeliveryserviceRegex', => using => { deliveryservice => '11', regex => '11', set_number => '0', }, }, 
'5' => { new => 'DeliveryserviceRegex', => using => { deliveryservice => '12', regex => '12', set_number => '0', }, }, 
'6' => { new => 'DeliveryserviceRegex', => using => { deliveryservice => '13', regex => '13', set_number => '0', }, }, 
'7' => { new => 'DeliveryserviceRegex', => using => { deliveryservice => '14', regex => '14', set_number => '0', }, }, 
); 

sub name {
		return "DeliveryserviceRegex";
}

sub get_definition { 
		my ( $self, $name ) = @_;
		return $definition_for{$name};
}

sub all_fixture_names {
		return keys %definition_for;
}

__PACKAGE__->meta->make_immutable;
1;
