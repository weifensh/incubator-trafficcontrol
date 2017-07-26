package main;
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
use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use DBI;
use JSON;
use Digest::SHA1 qw(sha1_hex);
use Data::Dumper;
use strict;
use warnings;
no warnings 'once';
use warnings 'all';
use Test::TestHelper;
use Test::TestHelper;
use Utils::Tenant;

#no_transactions=>1 ==> keep fixtures after every execution, beware of duplicate data!
#no_transactions=>0 ==> delete fixtures after every execution

BEGIN { $ENV{MOJO_MODE} = "test" }

my $schema = Schema->connect_to_database;
my $dbh    = Schema->database_handle;
my $t      = Test::Mojo->new('TrafficOps');

Test::TestHelper->unload_core_data($schema);
Test::TestHelper->load_core_data($schema);

#globals
my $root_tenant_id = get_tenant_id("root");

# building the below heirarchy,
# and creating an admin user for each tenant
#
# -root
#     |---A
#     |   |---A1
#     |   |   |
#     |   |   |---A1a
#     |   |   |---A1b, in-active
#     |   |
#     |   |---A2
#     |   |   |
#     |   |   |---A2a
#     |   |
#     |   |---A3, in-active
#     |   |   |
#     |   |   |---A3a
#     |
#     |---B
#     |   |---B1

# Count the 'response number'
my $responses_counter = sub {
    my $t = shift;
    my $json = decode_json( $t->tx->res->content->asset->slurp );
    my $r    = $json->{response};
    if ($r) {
        return scalar(@$r);
    }
    return 0;
};

# Count the 'response number', and compare to the give value
my $count_response_test = sub {
    my ( $t, $count ) = @_;
    return $t->success( is( $t->$responses_counter(), $count ) );
};

#Building up the setup
ok $t->post_ok( '/login', => form => { u => Test::TestHelper::ADMIN_ROOT_USER, p => Test::TestHelper::ADMIN_ROOT_USER_PASSWORD } )->status_is(302)
        ->or( sub { diag $t->tx->res->content->asset->{content}; } ), 'Should login?';

#verifying the basic cfg
ok $t->get_ok("/api/1.2/tenants")->status_is(200)->json_is( "/response/0/name", "root" )->or( sub { diag $t->tx->res->content->asset->{content}; } );;

my $tenants_data = {};
prepare_tenant("root", undef, $tenants_data);
prepare_tenant("none", undef, $tenants_data);
prepare_tenant("A", $root_tenant_id, $tenants_data);
prepare_tenant("A1", $tenants_data->{"A"}->{'id'}, $tenants_data);
prepare_tenant("A1a", $tenants_data->{"A1"}->{'id'}, $tenants_data);
prepare_tenant("A1b", $tenants_data->{"A1"}->{'id'}, $tenants_data);
prepare_tenant("A2", $tenants_data->{"A"}->{'id'}, $tenants_data);
prepare_tenant("A2a", $tenants_data->{"A2"}->{'id'}, $tenants_data);
prepare_tenant("A3", $tenants_data->{"A"}->{'id'}, $tenants_data);
prepare_tenant("A3a", $tenants_data->{"A3"}->{'id'}, $tenants_data);
prepare_tenant("B", $root_tenant_id, $tenants_data);
deactivate_tenant("A1b", $tenants_data);
deactivate_tenant("A3", $tenants_data);


ok $t->get_ok('/logout')->status_is(302)->or( sub { diag $t->tx->res->content->asset->{content}; } );

#Get the null tenants counters
ok $t->post_ok( '/login', => form => { u => Test::TestHelper::ADMIN_USER, p => Test::TestHelper::ADMIN_USER_PASSWORD } )->status_is(302)
        ->or( sub { diag $t->tx->res->content->asset->{content}; } ), 'Should login?';

my $fixture_num_of_tenants = $t->get_ok('/api/1.2/tenants')->status_is(200)->$responses_counter();
my $fixture_num_of_users = $t->get_ok('/api/1.2/users')->status_is(200)->$responses_counter();
my $fixture_num_of_dses = $t->get_ok('/api/1.2/deliveryservices')->status_is(200)->$responses_counter();

ok $t->get_ok('/logout')->status_is(302)->or( sub { diag $t->tx->res->content->asset->{content}; } );


########################################################################################
# All is ready - lets start testing
########################################################################################
#####Working as user from tenant "A1"
login_to_tenant_portal ("A1", $tenants_data);
my $num_of_tenants_can_be_accessed = 3; #A1, A1a, A1b
#sanity check on tenants - testing of tenant as a resource is taken care of in tenants.t
ok $t->get_ok('/api/1.2/tenants')->status_is(200)->$count_response_test($num_of_tenants_can_be_accessed+$fixture_num_of_tenants);
ok $t->get_ok('/api/1.2/users')->status_is(200)->$count_response_test(2*$num_of_tenants_can_be_accessed+$fixture_num_of_users);
ok $t->get_ok('/api/1.2/deliveryservices')->status_is(200)->$count_response_test($num_of_tenants_can_be_accessed+$fixture_num_of_dses);

#cannot change its tenancy
ok $t->put_ok('/api/1.2/user/current' => {Accept => 'application/json'} =>
        json => { user => { tenantId => $tenants_data->{"A"}->{'id'},
                            localPasswd => "pass",
                            confirmLocalPasswd => "pass2"} } )
        ->json_is( "/alerts/0/text" => "Invalid tenant. This tenant is not available to you for assignment.")
        ->status_is(400)->or( sub { diag $t->tx->res->content->asset->{content}; } )
    , 'Cannot change my tenancy: tenant: A1?';
#can change its tenancy to child (fail on another reason, currently on missing email,
# but if it will not be mandatory anymore it should fail on password mismatch)
ok $t->put_ok('/api/1.2/user/current' => {Accept => 'application/json'} =>
        json => { user => { tenantId => $tenants_data->{"A1a"}->{'id'},
                            localPasswd => "pass",
                            confirmLocalPasswd => "pass2"} } )
        ->json_is( "/alerts/0/text" => "email is required")
        ->status_is(400)->or( sub { diag $t->tx->res->content->asset->{content}; } )
    , 'Can change my tenancy: tenant: A1?';
ok $t->get_ok('/api/1.2/deliveryservices')->status_is(200)->$count_response_test($num_of_tenants_can_be_accessed+$fixture_num_of_dses);
logout_from_tenant();
#access to himself
test_tenants_allow_access ("A1", "A1", $tenants_data);
#access to child
test_tenants_allow_access ("A1", "A1a", $tenants_data);
#access to even if child is inactive
test_tenants_allow_access ("A1", "A1a", $tenants_data);
#No access to parent
test_tenants_block_access ("A1", "A", $tenants_data);
#No access to brother
test_tenants_block_access ("A1", "A2", $tenants_data);
#No access to nephew
test_tenants_block_access ("A1", "A2a", $tenants_data);
#No access to uncle
test_tenants_block_access ("A1", "B", $tenants_data);
#No access to grandfather
test_tenants_block_access ("A1", "root", $tenants_data);
#access to "no-tenant"
test_tenants_allow_access ("A1", "none", $tenants_data);

#####Working as user from inactive tenant "A3"
login_to_tenant_portal ("A3", $tenants_data);
$num_of_tenants_can_be_accessed = 0;
#sanity check on tenants - testing of tenant as a resource is taken care of in tenants.t
ok $t->get_ok('/api/1.2/tenants')->status_is(200)->$count_response_test(0);
ok $t->get_ok('/api/1.2/users')->status_is(200)->$count_response_test(0);
#cannot change its tenancy to non related
ok $t->put_ok('/api/1.2/user/current' => {Accept => 'application/json'} =>
        json => { user => { tenantId => $tenants_data->{"A1a"}->{'id'}} } )
        ->json_is( "/alerts/0/text" => "Invalid tenant. This tenant is not available to you for assignment.")
        ->status_is(400)->or( sub { diag $t->tx->res->content->asset->{content}; } )
    , 'Cannot change my tenancy: tenant: A1?';
ok $t->get_ok('/api/1.2/deliveryservices')->status_is(200)->$count_response_test(0);
logout_from_tenant();
#no access to anywhere
test_tenants_block_access ("A3", "A3", $tenants_data);
#child
test_tenants_block_access ("A3", "A1a", $tenants_data);
#to parent
test_tenants_block_access ("A3", "A", $tenants_data);
#No access to brother
test_tenants_block_access ("A3", "A2", $tenants_data);
#no access to "no-tenant"
test_tenants_block_access ("A3", "none", $tenants_data);



####Working as user from no tenant
login_to_tenant_portal ("none", $tenants_data);
$num_of_tenants_can_be_accessed = 0;
#sanity check on tenants - testing of tenant as a resource is taken care of in tenants.t
ok $t->get_ok('/api/1.2/tenants')->status_is(200)->$count_response_test($num_of_tenants_can_be_accessed+$fixture_num_of_tenants);
#cannot change its tenancy
ok $t->put_ok('/api/1.2/user/current' => {Accept => 'application/json'} =>
        json => { user => { tenantId => $tenants_data->{"A1a"}->{'id'}} } )
        ->json_is( "/alerts/0/text" => "Invalid tenant. This tenant is not available to you for assignment.")
        ->status_is(400)->or( sub { diag $t->tx->res->content->asset->{content}; } )
    , 'Cannot change my tenancy: tenant: A1?';
logout_from_tenant();
#access to himself
test_tenants_allow_access ("none", "none", $tenants_data);
#No access to tenant
test_tenants_block_access ("none", "A", $tenants_data);

########################################################################################
# All is done - lets cleanup
########################################################################################
ok $t->post_ok( '/login', => form => { u => Test::TestHelper::ADMIN_ROOT_USER, p => Test::TestHelper::ADMIN_ROOT_USER_PASSWORD } )->status_is(302)
        ->or( sub { diag $t->tx->res->content->asset->{content}; } ), 'Should login?';

clear_tenant("B", $tenants_data);
clear_tenant("A3a", $tenants_data);
clear_tenant("A3", $tenants_data);
clear_tenant("A2a", $tenants_data);
clear_tenant("A2", $tenants_data);
clear_tenant("A1b", $tenants_data);
clear_tenant("A1a", $tenants_data);
clear_tenant("A1", $tenants_data);
clear_tenant("A", $tenants_data);
clear_tenant("none", $tenants_data);
clear_tenant("root", $tenants_data);


ok $t->get_ok('/logout')->status_is(302)->or( sub { diag $t->tx->res->content->asset->{content}; } );
$dbh->disconnect();
done_testing();



#################### Utilities
sub get_tenant_id {
    my $name = shift;
    my $q    = "select id from tenant where name = \'$name\'";
    my $get_svr = $dbh->prepare($q);
    $get_svr->execute();
    my $p = $get_svr->fetchall_arrayref( {} );
    $get_svr->finish();
    my $id = $p->[0]->{id};
    return $id;
}

sub prepare_tenant {
    my $name = shift;
    my $parent_id = shift;
    my $tenants_data = shift;
    #adding a child tenant
    if ($name ne "root" and $name ne "none") {
        ok $t->post_ok('/api/1.2/tenants' => { Accept => 'application/json' } => json => {
                    "name" => $name, "active" => 1, "parentId" =>
                    $parent_id })->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
                ->json_is( "/response/name" => $name )
                ->json_is( "/response/active" => 1 )
                ->json_is( "/response/parentId" => $parent_id)
            , 'Created tenant $name?';
    }

    my $tenant_id = &get_tenant_id($name);

    #adding an admin user
    my $admin_username=$name."_admin";
    ok $t->post_ok('/api/1.2/users' => {Accept => 'application/json'} => json => {
                "username" => $admin_username,
                "fullName"=>$admin_username,
                "email" => $admin_username."\@tc.com",
                "localPasswd" => 'my-password',
                "confirmLocalPasswd"=> 'my-password',
                "role" => 4,
                "uid" => 1,
                "gid" => 1,
                "newUser"          => \1,
                #"registrationSent" => $row->registration_sent,
                "tenantId" => $tenant_id,
            })
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/username" =>  $admin_username )
            ->json_is( "/response/tenantId" =>  $tenant_id)
        , 'Success added user?';

    my $admin_userid = $schema->resultset('TmUser')->find( { username => $admin_username } )->id;

    #adding an admin user
    my $portal_username=$name."_portal";
    ok $t->post_ok('/api/1.2/users' => {Accept => 'application/json'} => json => {
                "username" => $portal_username,
                "fullName"=>$portal_username,
                "email" => $portal_username."\@tc.com",
                "localPasswd" => 'my-password',
                "confirmLocalPasswd"=> 'my-password',
                "role" => 4,
                "uid" => 1,
                "gid" => 1,
                "newUser"          => \1,
                #"registrationSent" => $row->registration_sent,
                "tenantId" => $tenant_id,
            })
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/username" =>  $portal_username )
            ->json_is( "/response/tenantId" =>  $tenant_id)
        , 'Success added user?';

    my $portal_userid = $schema->resultset('TmUser')->find( { username => $portal_username } )->id;

    # It creates new delivery services
    my $ds_name = $name."_ds1";
    my $ds_xml_id = $name."_ds1";
    ok $t->post_ok('/api/1.2/deliveryservices' => {Accept => 'application/json'} => json => {
                "xmlId" => $ds_xml_id,
                "displayName" => $ds_name,
                "protocol" => "1",
                "orgServerFqdn" => "http://10.75.168.91",
                "cdnName" => "cdn1",
                "tenantId" => $tenant_id,
                "profileId" => 300,
                "typeId" => "36",
                "multiSiteOrigin" => "0",
                "regionalGeoBlocking" => "1",
                "active" => "false",
                "dscp" => 0,
                "ipv6RoutingEnabled" => "true",
                "logsEnabled" => "true",
                "initialDispersion" => 0,
                "cdnId" => 100,
                "signed" => "false",
                "rangeRequestHandling" => 0,
                "geoLimit" => 0,
                "geoProvider" => 0,
                "qstringIgnore" => 0,
            })
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/0/xmlId" => $ds_xml_id)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/0/displayName" => $ds_name)
            ->json_is( "/response/0/tenantId" => $tenant_id)
        , 'Was the DS properly added and reported?';

    my $ds_id = $schema->resultset('Deliveryservice')->find( { xml_id => $ds_xml_id } )->id;

    # assign one ds to user with id=200
    ok $t->post_ok('/api/1.2/deliveryservice_user' => {Accept => 'application/json'} => json => {
                "userId" => $portal_userid,
                "deliveryServices" => [ $ds_id ]
            })
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/userId" => $portal_userid )
            ->json_is( "/response/deliveryServices/0" => $ds_id )
        , 'Does the delivery services assign details return?';

    add_tenant_record($tenants_data, $name, $tenant_id, 
        $admin_username, $admin_userid,
        $portal_username, $portal_userid,
        $ds_id, $ds_xml_id);
}

sub add_tenant_record {
    my $tenants_data = shift;
    my $tenant_name = shift;
    $tenants_data->{$tenant_name} = {
        'id' => shift,
        'admin_username' => shift,
        'admin_uid' => shift,
        'portal_username' => shift,
        'portal_uid' => shift,
        'ds_id' => shift,
        'ds_xml_id' => shift,
    };
}

sub clear_tenant {
    my $name = shift;
    my $tenants_data = shift;


    #deleting the DS
    ok $t->delete_ok('/api/1.2/deliveryservice_user/'.$tenants_data->{$name}->{'ds_id'}.'/'.$tenants_data->{$name}->{'portal_uid'} => {Accept => 'application/json'})
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , 'Does the delivery services assign deleted?';

    ok $t->delete_ok('/api/1.2/deliveryservices/' . $tenants_data->{$name}->{'ds_id'})->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } );

    if ($name eq "root" or $name eq "none") {
        return;
    }
    #deleting the user - as the user do operations this is not so simple. We move it to the root tenant and the fixture cleanup will do
    my $json_p = decode_json( $t->get_ok('/api/1.2/users/'.$tenants_data->{$name}->{'portal_uid'})->tx->res->content->asset->slurp );
    my $response    = $json_p->{response}[0];
    $response->{"tenantId"} = get_tenant_id("root");
    ok $t->put_ok('/api/1.2/users/'.$tenants_data->{$name}->{'portal_uid'} => {Accept => 'application/json'} => json => $response)
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , 'Success move user?';

    #deleting the user - as the user do operations this is not so simple. We move it to the root tenant and the fixture cleanup will do
    my $json = decode_json( $t->get_ok('/api/1.2/users/'.$tenants_data->{$name}->{'admin_uid'})->tx->res->content->asset->slurp );
    my $response_p    = $json->{response}[0];
    $response_p->{"tenantId"} = get_tenant_id("root");
    ok $t->put_ok('/api/1.2/users/'.$tenants_data->{$name}->{'admin_uid'} => {Accept => 'application/json'} => json => $response_p)
        ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , 'Success move user?';

    ok $t->delete_ok('/api/1.2/tenants/' . $tenants_data->{$name}->{'id'})->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } );
}

sub deactivate_tenant {
    my $name = shift;
    my $tenants_data = shift;

    my $json = decode_json( $t->get_ok('/api/1.2/tenants/'.$tenants_data->{$name}->{'id'})->tx->res->content->asset->slurp );
    my $response    = $json->{response}[0];
    $response->{"active"} = 0;
    ok $t->put_ok('/api/1.2/tenants/'.$tenants_data->{$name}->{'id'} => {Accept => 'application/json'} => json => $response)
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , 'Success deactivate tenant '.$name.'?';
}

sub test_tenants_allow_access {
    my $login_tenant = shift;
    my $resource_tenant = shift;
    my $tenants_data = shift;

    test_user_resource_read_allow_access ($login_tenant, $resource_tenant, $tenants_data);
    test_user_resource_write_allow_access ($login_tenant, $resource_tenant, $tenants_data);
    test_ds_resource_read_allow_access ($login_tenant, $resource_tenant, $tenants_data);
    test_ds_resource_write_allow_access ($login_tenant, $resource_tenant, $tenants_data);
}
sub test_tenants_block_access {
    my $login_tenant = shift;
    my $resource_tenant = shift;
    my $tenants_data = shift;

    test_user_resource_read_block_access ($login_tenant, $resource_tenant, $tenants_data);
    test_user_resource_write_block_access ($login_tenant, $resource_tenant, $tenants_data);
    test_ds_resource_read_block_access ($login_tenant, $resource_tenant, $tenants_data);
    test_ds_resource_write_block_access ($login_tenant, $resource_tenant, $tenants_data);
}

sub login_to_tenant_admin {
    my $login_tenant_name = shift;
    my $tenants_data = shift;

    ok $t->post_ok( '/login', => form => { u => $tenants_data->{$login_tenant_name}->{'admin_username'}, p => "my-password" } )->status_is(302)
            ->or( sub { diag $t->tx->res->content->asset->{content}; } ), 'Logged in as admin:'.$login_tenant_name.'?';
}

sub login_to_tenant_portal {
    my $login_tenant_name = shift;
    my $tenants_data = shift;

    ok $t->post_ok( '/login', => form => { u => $tenants_data->{$login_tenant_name}->{'portal_username'}, p => "my-password" } )->status_is(302)
            ->or( sub { diag $t->tx->res->content->asset->{content}; } ), 'Logged in as portal:'.$login_tenant_name.'?';
}

sub logout_from_tenant {
    ok $t->get_ok('/logout')->status_is(302)->or( sub { diag $t->tx->res->content->asset->{content}; } );
}

sub is_tenant_active{
    my $tenant_name = shift;
    if ($tenant_name eq "none"){
        return 1;
    }
    return $schema->resultset('Tenant')->find( { name => $tenant_name } )->active;
}

sub test_user_resource_read_allow_access {
    my $login_tenant = shift;
    my $resource_tenant = shift;
    my $tenants_data = shift;
    login_to_tenant_admin($login_tenant, $tenants_data);

    ok $t->get_ok('/api/1.2/users/'.$tenants_data->{$resource_tenant}->{'admin_uid'})
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/0/username" =>  $tenants_data->{$resource_tenant}->{'admin_username'} )
            ->json_is( "/response/0/tenantId" =>  $tenants_data->{$resource_tenant}->{'id'})
        , 'Success read user: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    logout_from_tenant();
}

sub test_user_resource_read_block_access {
    my $login_tenant = shift;
    my $resource_tenant = shift;
    my $tenants_data = shift;
    login_to_tenant_admin($login_tenant, $tenants_data);

    ok $t->get_ok('/api/1.2/users/'.$tenants_data->{$resource_tenant}->{'admin_uid'})
            ->status_is(403)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , '403 for read user: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    logout_from_tenant();
}

sub test_user_resource_write_allow_access {
    my $login_tenant = shift;
    my $resource_tenant = shift;
    my $tenants_data = shift;
    login_to_tenant_admin($login_tenant, $tenants_data);

    #adding a user
    my $new_username="test_user";
    ok $t->post_ok('/api/1.2/users' => {Accept => 'application/json'} => json => {
                "username" => $new_username,
                "fullName"=>$new_username,
                "email" => $new_username."\@tc.com",
                "localPasswd" => 'my-password',
                "confirmLocalPasswd"=> 'my-password',
                "role" => 4,
                "tenantId" => $tenants_data->{$resource_tenant}->{'id'},
            })
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/username" =>  $new_username )
            ->json_is( "/response/tenantId" =>  $tenants_data->{$resource_tenant}->{'id'})
        , 'Success add user: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';


    my $new_user_record = $schema->resultset('TmUser')->find( { username => $new_username } );
    $t->success(defined($new_user_record));
    if (!defined($new_user_record)){
        return;
    }
    my $new_userid = $new_user_record->id;

    #get the data
    my $json = decode_json( $t->get_ok('/api/1.2/users/'.$new_userid)->tx->res->content->asset->slurp );
    my $response2edit    = $json->{response}[0];
    $t->success(is($new_username,                             $response2edit->{"username"}));
    $t->success(is($tenants_data->{$resource_tenant}->{'id'}, $response2edit->{"tenantId"}));

    #change the email
    $response2edit->{"email"} = $new_username."\@tc2.com";
    ok $t->put_ok('/api/1.2/users/'.$new_userid => {Accept => 'application/json'} => json => $response2edit)
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/username" =>  $response2edit->{"username"})
            ->json_is( "/response/email" =>  $response2edit->{"email"} )
            ->json_is( "/response/tenantId" =>  $response2edit->{"tenantId"})
        , 'Success change user email: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    #change the tenant to my tenant
    $response2edit->{"tenantId"} = $tenants_data->{$login_tenant}->{'id'};
    ok $t->put_ok('/api/1.2/users/'.$new_userid => {Accept => 'application/json'} => json => $response2edit)
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/username" =>  $response2edit->{"username"})
            ->json_is( "/response/email" =>  $response2edit->{"email"} )
            ->json_is( "/response/tenantId" =>  $response2edit->{"tenantId"})
        , 'Success change user tenant to login: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    #change the tenant to his tenant
    $response2edit->{"tenantId"} = $tenants_data->{$resource_tenant}->{'id'};
    ok $t->put_ok('/api/1.2/users/'.$new_userid => {Accept => 'application/json'} => json => $response2edit)
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/username" =>  $response2edit->{"username"})
            ->json_is( "/response/email" =>  $response2edit->{"email"} )
            ->json_is( "/response/tenantId" =>  $response2edit->{"tenantId"})
        , 'Success change user tenant to orig: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    logout_from_tenant();

    #deleting the user for cleanup - no API for that yet
    ok $schema->resultset('TmUser')->find( { id => $new_userid } )->delete();
}

sub test_user_resource_write_block_access {
    my $login_tenant = shift;
    my $resource_tenant = shift;
    my $tenants_data = shift;
    login_to_tenant_admin($login_tenant, $tenants_data);

    my $is_login_tenant_active = is_tenant_active($login_tenant);
    #adding a user
    my $new_username="test_user";
    ok $t->post_ok('/api/1.2/users' => {Accept => 'application/json'} => json => {
                "username" => $new_username,
                "fullName"=>$new_username,
                "email" => $new_username."\@tc.com",
                "localPasswd" => 'my-password',
                "confirmLocalPasswd"=> 'my-password',
                "role" => 4,
                "tenantId" => $tenants_data->{$resource_tenant}->{'id'},
            })
            ->status_is(400)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/alerts/0/text" => "Invalid tenant. This tenant is not available to you for assignment." )
        , 'Cannot add user: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';


    my $new_user_record = $schema->resultset('TmUser')->find( { username => $new_username } );
    $t->success(!defined($new_user_record));
    if (defined($new_user_record)){
        return;
    }

    #get the data for trying to update the user
    logout_from_tenant();
    login_to_tenant_admin("root", $tenants_data);
    my $json = decode_json( $t->get_ok('/api/1.2/users/'.$tenants_data->{$resource_tenant}->{'admin_uid'})->tx->res->content->asset->slurp );
    my $orig_response = $json->{response}[0];
    my $response2edit = { %$orig_response };
    $t->success(is($tenants_data->{$resource_tenant}->{'admin_username'}, $response2edit->{"username"}));
    $t->success(is($tenants_data->{$resource_tenant}->{'id'},             $response2edit->{"tenantId"}));
    my $new_userid = $tenants_data->{$resource_tenant}->{'admin_uid'};
    logout_from_tenant();
    login_to_tenant_admin($login_tenant, $tenants_data);

    #change the email
    $response2edit->{"email"} = $new_username."\@tc2.com";
    ok $t->put_ok('/api/1.2/users/'.$new_userid => {Accept => 'application/json'} => json => $response2edit)
            ->status_is(403)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , 'Cannot change user email: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';
    $response2edit = { %$orig_response };

    #change the tenant to my tenant
    $response2edit->{"tenantId"} = $tenants_data->{$login_tenant}->{'id'};
    ok $t->put_ok('/api/1.2/users/'.$new_userid => {Accept => 'application/json'} => json => $response2edit)
            ->status_is(403)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , 'Cannot change user tenant to login: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';
    $response2edit = { %$orig_response };

    #verify no change
    logout_from_tenant();
    login_to_tenant_admin("root", $tenants_data);
    my $json1 = decode_json( $t->get_ok('/api/1.2/users/'.$tenants_data->{$resource_tenant}->{'admin_uid'})->tx->res->content->asset->slurp );
    my $new_response = $json1->{response}[0];
    $t->success(is($orig_response->{"username"}, $new_response->{"username"}));
    $t->success(is($orig_response->{"tenantId"}, $new_response->{"tenantId"}));
    $t->success(is($orig_response->{"email"},    $new_response->{"email"}));
    logout_from_tenant();
    login_to_tenant_admin($login_tenant, $tenants_data);

    #create a user with my tenancy and change his tenancy to the tested resource tenant
    #adding a user
    logout_from_tenant();
    login_to_tenant_admin("root", $tenants_data);
    my $new_username2="test_user";
    ok $t->post_ok('/api/1.2/users' => {Accept => 'application/json'} => json => {
                "username" => $new_username2,
                "fullName"=>$new_username2,
                "email" => $new_username2."\@tc.com",
                "localPasswd" => 'my-password',
                "confirmLocalPasswd"=> 'my-password',
                "role" => 4,
                "tenantId" => $tenants_data->{$login_tenant}->{'id'},
            })
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/username" =>  $new_username2 )
            ->json_is( "/response/tenantId" =>  $tenants_data->{$login_tenant}->{'id'})
        , 'Success add user: login tenant:'.$login_tenant.'?';

    #get its data
    my $new_user_record2 = $schema->resultset('TmUser')->find( { username => $new_username2 } );
    $t->success(defined($new_user_record2));
    if (!defined($new_user_record2)){
        return;
    }
    my $new_userid2 = $new_user_record2->id;
    my $json2 = decode_json( $t->get_ok('/api/1.2/users/'.$new_userid2)->tx->res->content->asset->slurp );
    my $response2edit2    = $json2->{response}[0];
    $t->success(is($new_username2,                         $response2edit2->{"username"}));
    $t->success(is($tenants_data->{$login_tenant}->{'id'}, $response2edit2->{"tenantId"}));
    logout_from_tenant();
    login_to_tenant_admin($login_tenant, $tenants_data);

    #changing only its tenancy (403 if the basic resource cannot be accessed, 400 if the change is invalid)
    $response2edit2->{"tenantId"} = $tenants_data->{$resource_tenant}->{'id'};
    ok $t->put_ok('/api/1.2/users/'.$new_userid2 => {Accept => 'application/json'} => json => $response2edit2)
            ->status_is($is_login_tenant_active ? 400 : 403)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/alerts/0/text" => $is_login_tenant_active ? "Invalid tenant. This tenant is not available to you for assignment." : "Forbidden: User is not available for your tenant.")
        , 'Cannot change user tenant to the target resource tenant: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    logout_from_tenant();

    #deleting the user for cleanup - no API for that yet
    ok $schema->resultset('TmUser')->find( { id => $new_userid2 } )->delete();
}

sub test_ds_resource_read_allow_access {
    my $login_tenant = shift;
    my $resource_tenant = shift;
    my $tenants_data = shift;
    login_to_tenant_portal($login_tenant, $tenants_data);

    ok $t->get_ok('/api/1.2/deliveryservices/'.$tenants_data->{$resource_tenant}->{'ds_id'})
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/0/xmlId" =>  $tenants_data->{$resource_tenant}->{'ds_xml_id'} )
            ->json_is( "/response/0/tenantId" =>  $tenants_data->{$resource_tenant}->{'id'})
        , 'Success read ds: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    ok $t->get_ok('/api/1.2/deliveryservices/'.$tenants_data->{$resource_tenant}->{'ds_id'}.'/health')
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , 'Success for read ds health: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    ok $t->get_ok('/api/1.2/deliveryservices/'.$tenants_data->{$resource_tenant}->{'ds_id'}.'/capacity')
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , 'Success for read ds capacity: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    #comment out for now - crash - maybe because regex is not defined
    #ok $t->get_ok('/api/1.2/deliveryservices/'.$tenants_data->{$resource_tenant}->{'ds_id'}.'/routing')
    #        ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
    #    , 'Success for read ds routing: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    ok $t->get_ok('/api/1.2/deliveryservices/'.$tenants_data->{$resource_tenant}->{'ds_id'}.'/state')
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , 'Success for read ds state: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    logout_from_tenant();
}

sub test_ds_resource_read_block_access {
    my $login_tenant = shift;
    my $resource_tenant = shift;
    my $tenants_data = shift;
    login_to_tenant_admin($login_tenant, $tenants_data);

    ok $t->get_ok('/api/1.2/deliveryservices/'.$tenants_data->{$resource_tenant}->{'ds_id'})
            ->status_is(403)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , '403 for read ds: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    ok $t->get_ok('/api/1.2/deliveryservices/'.$tenants_data->{$resource_tenant}->{'ds_id'}.'/health')
            ->status_is(403)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , '403 for read ds health: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    ok $t->get_ok('/api/1.2/deliveryservices/'.$tenants_data->{$resource_tenant}->{'ds_id'}.'/capacity')
            ->status_is(403)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , '403 for read ds capacity: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    ok $t->get_ok('/api/1.2/deliveryservices/'.$tenants_data->{$resource_tenant}->{'ds_id'}.'/routing')
            ->status_is(403)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , '403 for read ds routing: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    ok $t->get_ok('/api/1.2/deliveryservices/'.$tenants_data->{$resource_tenant}->{'ds_id'}.'/state')
            ->status_is(403)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , '403 for read ds state: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    logout_from_tenant();
}

sub test_ds_resource_write_allow_access {
    my $login_tenant = shift;
    my $resource_tenant = shift;
    my $tenants_data = shift;
    login_to_tenant_portal($login_tenant, $tenants_data);

    #adding a ds
    my $new_ds_xml_id="test_ds";
    ok $t->post_ok('/api/1.2/deliveryservices' => {Accept => 'application/json'} => json => {
                "xmlId" => $new_ds_xml_id,
                "displayName" => $new_ds_xml_id,
                "protocol" => "1",
                "orgServerFqdn" => "http://10.75.168.91",
                "cdnName" => "cdn1",
                "tenantId" => $tenants_data->{$resource_tenant}->{'id'},
                "profileId" => 300,
                "typeId" => "36",
                "multiSiteOrigin" => "0",
                "regionalGeoBlocking" => "1",
                "active" => "false",
                "dscp" => 0,
                "ipv6RoutingEnabled" => "true",
                "logsEnabled" => "true",
                "initialDispersion" => 0,
                "cdnId" => 100,
                "signed" => "false",
                "rangeRequestHandling" => 0,
                "geoLimit" => 0,
                "geoProvider" => 0,
                "qstringIgnore" => 0,
            })
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/0/xmlId" => $new_ds_xml_id)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/0/displayName" => $new_ds_xml_id)
            ->json_is( "/response/0/tenantId" => $tenants_data->{$resource_tenant}->{'id'})
        , 'Success add ds: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';


    my $new_ds_record = $schema->resultset('Deliveryservice')->find( { xml_id => $new_ds_xml_id } );
    $t->success(defined($new_ds_record));
    if (!defined($new_ds_record)){
        return;
    }
    my $new_ds_id = $new_ds_record->id;

    #get the data
    my $json = decode_json( $t->get_ok('/api/1.2/deliveryservices/'.$new_ds_id)->tx->res->content->asset->slurp );
    my $response2edit = $json->{response}[0];
    $t->success(is($new_ds_xml_id,                            $response2edit->{"xmlId"}));
    $t->success(is($tenants_data->{$resource_tenant}->{'id'}, $response2edit->{"tenantId"}));

    #change the "orgServerFqdn"
    $response2edit->{"orgServerFqdn"} = "http://10.75.168.92";
    ok $t->put_ok('/api/1.2/deliveryservices/'.$new_ds_id => {Accept => 'application/json'} => json => $response2edit)
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/0/xmlId" =>  $response2edit->{"xmlId"})
            ->json_is( "/response/0/orgServerFqdn" =>  $response2edit->{"orgServerFqdn"} )
            ->json_is( "/response/0/tenantId" =>  $response2edit->{"tenantId"})
        , 'Success change ds orgServerFqdn: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    #change the tenant to my tenant
    $response2edit->{"tenantId"} = $tenants_data->{$login_tenant}->{'id'};
    ok $t->put_ok('/api/1.2/deliveryservices/'.$new_ds_id => {Accept => 'application/json'} => json => $response2edit)
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/0/xmlId" =>  $response2edit->{"xmlId"})
            ->json_is( "/response/0/orgServerFqdn" =>  $response2edit->{"orgServerFqdn"} )
            ->json_is( "/response/0/tenantId" =>  $response2edit->{"tenantId"})
        , 'Success change ds tenant to login: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    #change the tenant back to his tenant
    $response2edit->{"tenantId"} = $tenants_data->{$resource_tenant}->{'id'};
    ok $t->put_ok('/api/1.2/deliveryservices/'.$new_ds_id => {Accept => 'application/json'} => json => $response2edit)
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/0/xmlId" =>  $response2edit->{"xmlId"})
            ->json_is( "/response/0/orgServerFqdn" =>  $response2edit->{"orgServerFqdn"} )
            ->json_is( "/response/0/tenantId" =>  $response2edit->{"tenantId"})
        , 'Success change ds tenant to orig: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    #delete the ds for test and cleanup
    ok $t->delete_ok('/api/1.2/deliveryservices/'.$new_ds_id => {Accept => 'application/json'} => json => $response2edit)
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , 'Success delete ds: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    logout_from_tenant();
}

sub test_ds_resource_write_block_access {
    my $login_tenant = shift;
    my $resource_tenant = shift;
    my $tenants_data = shift;

    my $is_login_tenant_active = is_tenant_active($login_tenant);
    login_to_tenant_admin($login_tenant, $tenants_data);

    #adding a ds
    my $new_ds_xml_id="test_ds";
    ok $t->post_ok('/api/1.2/deliveryservices' => {Accept => 'application/json'} => json => {
                "xmlId" => $new_ds_xml_id,
                "displayName" => $new_ds_xml_id,
                "protocol" => "1",
                "orgServerFqdn" => "http://10.75.168.91",
                "cdnName" => "cdn1",
                "tenantId" => $tenants_data->{$resource_tenant}->{'id'},
                "profileId" => 300,
                "typeId" => "36",
                "multiSiteOrigin" => "0",
                "regionalGeoBlocking" => "1",
                "active" => "false",
                "dscp" => 0,
                "ipv6RoutingEnabled" => "true",
                "logsEnabled" => "true",
                "initialDispersion" => 0,
                "cdnId" => 100,
                "signed" => "false",
                "rangeRequestHandling" => 0,
                "geoLimit" => 0,
                "geoProvider" => 0,
                "qstringIgnore" => 0,
            })
            ->status_is(400)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/alerts/0/text" => "Invalid tenant. This tenant is not available to you for delivery-service assignment.")
        , 'Cannot add ds: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';


    my $new_ds_record = $schema->resultset('Deliveryservice')->find( { xml_id => $new_ds_xml_id } );
    $t->success(!defined($new_ds_record));
    if (defined($new_ds_record)){
        return;
    }

    #get the data for trying to update the user
    logout_from_tenant();
    login_to_tenant_admin("root", $tenants_data);
    my $json = decode_json( $t->get_ok('/api/1.2/deliveryservices/'.$tenants_data->{$resource_tenant}->{'ds_id'})->tx->res->content->asset->slurp );
    my $orig_response = $json->{response}[0];
    my $response2edit = { %$orig_response };
    $t->success(is($tenants_data->{$resource_tenant}->{'ds_xml_id'}, $response2edit->{"xmlId"}));
    $t->success(is($tenants_data->{$resource_tenant}->{'id'},        $response2edit->{"tenantId"}));
    my $new_ds_id = $tenants_data->{$resource_tenant}->{'ds_id'};
    logout_from_tenant();
    login_to_tenant_admin($login_tenant, $tenants_data);

    #change the "orgServerFqdn"
    $response2edit->{"orgServerFqdn"} = "http://10.75.168.92";
    ok $t->put_ok('/api/1.2/deliveryservices/'.$new_ds_id => {Accept => 'application/json'} => json => $response2edit)
            ->status_is(403)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , 'Cannot change ds orgServerFqdn: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';
    $response2edit = { %$orig_response };

    #change the tenant to my tenant
    $response2edit->{"tenantId"} = $tenants_data->{$login_tenant}->{'id'};
    ok $t->put_ok('/api/1.2/deliveryservices/'.$new_ds_id => {Accept => 'application/json'} => json => $response2edit)
            ->status_is(403)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , 'Cannot change ds tenant to login: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';
    $response2edit = { %$orig_response };

    #verify no change
    logout_from_tenant();
    login_to_tenant_admin("root", $tenants_data);
    my $json1 = decode_json( $t->get_ok('/api/1.2/deliveryservices/'.$new_ds_id)->tx->res->content->asset->slurp );
    my $new_response = $json1->{response}[0];
    $t->success(is($orig_response->{"xmlId"}, $new_response->{"xmlId"}));
    $t->success(is($orig_response->{"tenantId"}, $new_response->{"tenantId"}));
    $t->success(is($orig_response->{"orgServerFqdn"},    $new_response->{"orgServerFqdn"}));
    logout_from_tenant();
    login_to_tenant_admin($login_tenant, $tenants_data);

    ok $t->delete_ok('/api/1.2/deliveryservices/'.$new_ds_id => {Accept => 'application/json'})
            ->status_is(403)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , 'Cannot delete ds: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    #create a ds with my tenancy and change his tenancy to the tested resource tenant
    #adding a ds
    logout_from_tenant();
    login_to_tenant_admin("root", $tenants_data);
    my $new_ds_xml_id2="test_ds2";
    ok $t->post_ok('/api/1.2/deliveryservices' => {Accept => 'application/json'} => json => {
                "xmlId" => $new_ds_xml_id2,
                "displayName" => $new_ds_xml_id,
                "protocol" => "1",
                "orgServerFqdn" => "http://10.75.168.91",
                "cdnName" => "cdn1",
                "tenantId" => $tenants_data->{$login_tenant}->{'id'},
                "profileId" => 300,
                "typeId" => "36",
                "multiSiteOrigin" => "0",
                "regionalGeoBlocking" => "1",
                "active" => "false",
                "dscp" => 0,
                "ipv6RoutingEnabled" => "true",
                "logsEnabled" => "true",
                "initialDispersion" => 0,
                "cdnId" => 100,
                "signed" => "false",
                "rangeRequestHandling" => 0,
                "geoLimit" => 0,
                "geoProvider" => 0,
                "qstringIgnore" => 0,
            })
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/response/0/xmlId" =>  $new_ds_xml_id2 )
            ->json_is( "/response/0/tenantId" =>  $tenants_data->{$login_tenant}->{'id'})
        , 'Success add ds: login tenant:'.$login_tenant.'?';

    #get its data
    my $new_ds_record2 = $schema->resultset('Deliveryservice')->find( { xml_id => $new_ds_xml_id2 } );
    $t->success(defined($new_ds_record2));
    if (!defined($new_ds_record2)){
        return;
    }
    my $new_ds_id2 = $new_ds_record2->id;
    my $json2 = decode_json( $t->get_ok('/api/1.2/deliveryservices/'.$new_ds_id2)->tx->res->content->asset->slurp );
    my $response2edit2    = $json2->{response}[0];
    $t->success(is($new_ds_xml_id2,                           $response2edit2->{"xmlId"}));
    $t->success(is($tenants_data->{$login_tenant}->{'id'}, $response2edit2->{"tenantId"}));
    logout_from_tenant();
    login_to_tenant_admin($login_tenant, $tenants_data);

    #changing only its tenancy
    $response2edit2->{"tenantId"} = $tenants_data->{$resource_tenant}->{'id'};
    ok $t->put_ok('/api/1.2/deliveryservices/'.$new_ds_id2 => {Accept => 'application/json'} => json => $response2edit2)
            ->status_is($is_login_tenant_active ? 400 : 403)->or( sub { diag $t->tx->res->content->asset->{content}; } )
            ->json_is( "/alerts/0/text" => $is_login_tenant_active ? "Invalid tenant. This tenant is not available to you for assignment." : "Forbidden. Delivery-service tenant is not available to the user.")
        , 'Cannot change ds tenant to the target resource tenant: login tenant:'.$login_tenant.' resource tenant: '.$resource_tenant.'?';

    logout_from_tenant();

    #deleting the ds for cleanup - no API for that yet
    logout_from_tenant();
    login_to_tenant_admin("root", $tenants_data);
    ok $t->delete_ok('/api/1.2/deliveryservices/'.$new_ds_id2 => {Accept => 'application/json'} => json => $response2edit2)
            ->status_is(200)->or( sub { diag $t->tx->res->content->asset->{content}; } )
        , 'Deleted the added tenant:'. $login_tenant.' resource tenant: '.$resource_tenant.'?';
    logout_from_tenant();
}
