package RapidoILL::Exceptions;

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use Koha::Exceptions;

use Exception::Class (
    'RapidoILL::Exception' => {
        isa         => 'Koha::Exception',
        description => 'Generic Rapido ILL plugin exception',
    },
    'RapidoILL::Exception::BadConfig' => {
        isa         => 'RapidoILL::Exception',
        description => 'A configuration entry has an unsupported value',
        fields      => [ 'entry', 'value' ],
    },
    'RapidoILL::Exception::BadParameter' => {
        isa         => 'RapidoILL::Exception',
        description => 'One or more parameters are wrong',
    },
    'RapidoILL::Exception::BadPickupLocation' => {
        isa         => 'RapidoILL::Exception',
        description => 'The passed pickupLocation attribute does not contain a valid structure',
        fields      => ['value']
    },
    'RapidoILL::Exception::InconsistentStatus' => {
        isa         => 'RapidoILL::Exception',
        description => 'Request status inconsistent with the requested action',
        fields      => [ 'expected', 'got' ]
    },
    'RapidoILL::Exception::InvalidCentralserver' => {
        isa         => 'RapidoILL::Exception',
        description => 'Passed central server is invalid',
        fields      => ['central_server']
    },
    'RapidoILL::Exception::InvalidStringNormalizer' => {
        isa         => 'RapidoILL::Exception',
        description => 'Passed string normalizer method is invalid',
        fields      => ['normalizer']
    },
    'RapidoILL::Exception::MissingConfigEntry' => {
        isa         => 'RapidoILL::Exception',
        description => 'A mandatory configuration entry is missing',
        fields      => ['entry']
    },
    'RapidoILL::Exception::MissingMapping' => {
        isa         => 'RapidoILL::Exception',
        description => 'Mapping returns undef',
        fields      => [ 'section', 'key' ]
    },
    'RapidoILL::Exception::MissingParameter' => {
        isa         => 'RapidoILL::Exception',
        description => 'Required parameter is missing',
        fields      => ['param']
    },
    'RapidoILL::Exception::UnknownItemId' => {
        isa         => 'RapidoILL::Exception',
        description => 'Passed item_id is invalid',
        fields      => ['item_id']
    },
    'RapidoILL::Exception::UnknownBiblioId' => {
        isa         => 'RapidoILL::Exception',
        description => 'Passed biblio_id is invalid',
        fields      => ['biblio_id']
    },
    'RapidoILL::Exception::UnhandledException' => {
        isa         => 'RapidoILL::Exception',
        description => 'Unhandled exception',
    },
    'RapidoILL::Exception::RequestFailed' => {
        isa         => 'RapidoILL::Exception',
        description => 'HTTP request error response',
        fields      => [ 'method', 'response' ]
    },
    'RapidoILL::Exception::OAuth2::AuthError' => {
        isa         => 'RapidoILL::Exception',
        description => 'Error authenticating against Rapido ILL',
    },
);

1;
