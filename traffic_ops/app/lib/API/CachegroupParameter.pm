package API::CachegroupParameter;
#
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
#

use UI::Utils;
use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

sub index {
	my $self = shift;
	my @data;
	my $orderby = $self->param('orderby') || "cachegroup";
	my $rs_data = $self->db->resultset("CachegroupParameter")->search( undef, { order_by => $orderby } );
	while ( my $row = $rs_data->next ) {
		push(
			@data, {
				"cachegroup"   => $row->cachegroup->name,
				"parameter"    => $row->parameter->id,
				"last_updated" => $row->last_updated,
			}
		);
	}
	$self->success( { "cachegroupParameters" => \@data } );
}

1;
