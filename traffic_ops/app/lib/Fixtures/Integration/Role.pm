package Fixtures::Integration::Role;

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
	## id => 1
	'0' => {
		new => 'Role',
		using => {
			name => 'admin',
			description => 'super-user',
			priv_level => '30',
		},
	},
	## id => 2
	'1' => {
		new => 'Role',
		using => {
			name => 'disallowed',
			description => 'block all access',
			priv_level => '0',
		},
	},
	## id => 3
	'2' => {
		new => 'Role',
		using => {
			name => 'migrations',
			description => 'database migrations user - DO NOT REMOVE',
			priv_level => '20',
		},
	},
	## id => 4
	'3' => {
		new => 'Role',
		using => {
			name => 'operations',
			description => 'block all access',
			priv_level => '20',
		},
	},
	## id => 5
	'4' => {
		new => 'Role',
		using => {
			name => 'portal',
			description => 'Portal User',
			priv_level => '2',
		},
	},
	## id => 6
	'5' => {
		new => 'Role',
		using => {
			name => 'read-only user',
			description => 'block all access',
			priv_level => '10',
		},
	},
);

sub name {
		return "Role";
}

sub get_definition {
		my ( $self,
			$name ) = @_;
		return $definition_for{$name};
}

sub all_fixture_names {
	# sort by db name to guarantee insertion order
	return (sort { $definition_for{$a}{using}{name} cmp $definition_for{$b}{using}{name} } keys %definition_for);
}

__PACKAGE__->meta->make_immutable;
1;
