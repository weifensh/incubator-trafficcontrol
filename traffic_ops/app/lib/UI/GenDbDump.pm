package UI::GenDbDump;
#
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#	 http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
#
use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

sub dbdump {
	my $self = shift;
	my $filename = $self->param('filename');

	my $db_user = $Schema::user;
	my $db_pass = $Schema::pass;
	my $db_name = $Schema::dsn;
	my $host;
	my $port;
	my $dsn = $Schema::dsn;
	($db_name, $host, $port) = $dsn =~ /:database=(\w+);host=(\w+);port=(\d+)/;

	my $cmd = "pg_dump -U " . $db_user . " -h localhost -C --column-insert";
	my $extension = ".psql";

	my $data = `$cmd`;

	$self->res->headers->content_type("application/download");
	$self->res->headers->content_disposition( "attachment; filename=\"" . $filename . "\"" );
	$self->render( data => $data );
}

1;
