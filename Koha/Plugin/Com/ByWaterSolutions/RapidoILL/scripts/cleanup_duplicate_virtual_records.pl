#!/usr/bin/env perl

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

=head1 NAME

cleanup_duplicate_virtual_records.pl - Remove orphan duplicate virtual bib/item
records left behind by the [#223] double-virtual-creation bug.

=head1 SYNOPSIS

    # DRY RUN (default): report what would be deleted, change nothing
    perl cleanup_duplicate_virtual_records.pl

    # Actually delete the orphan records
    perl cleanup_duplicate_virtual_records.pl --confirm

=head1 DESCRIPTION

Before the [#223] fix, a replayed borrower creation action (e.g. the pod
re-sending ITEM_SHIPPED with a newer lastUpdated) could make the plugin create
a B<second> virtual bib/item for the same ILL request. The second item collided
with the barcode of the first, so it was created with a C<-N> suffix, and the
ILL request/hold was re-pointed to that C<-N> record. The original
(base-barcode) record was left B<orphaned>: not referenced by any ILL request.

This script finds those orphan pairs and deletes the orphan record, freeing the
base barcode. It is intentionally conservative:

A pair is only acted upon when B<all> of the following hold:

  * a C<< <barcode>-N >> virtual item exists whose base-barcode item also exists;
  * B<both> items are RapidoILL virtual items (they carry the configured
    per-pod virtual-item note, e.g. "Additional processing required (ILL)");
  * the C<-N> biblio B<is> referenced by exactly one RapidoILL ILL request;
  * the base biblio is B<not> referenced by any ILL request (it is the orphan);
  * neither item is currently checked out.

Legitimate collisions with B<real owned items> (where the base barcode belongs
to a normal catalogued item) are never touched, because the base item would not
carry the virtual-item note.

Deletion is performed through C<< $plugin->delete_virtual_biblio >>, which
cancels holds, returns any checkout, deletes items and then the biblio.

=head1 OPTIONS

    --confirm         Perform the deletions. Without this flag the script only
                      reports (dry run).
    --limit <n>       Only process the first <n> candidate pairs.
    --illrequest <id> Only process the pair whose -N biblio is referenced by
                      this ILL request id (repeatable).
    --verbose|-v      Show per-pair detail.
    --help|-h         This help.

=cut

use Modern::Perl;
use utf8;

use Getopt::Long;
use Try::Tiny;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

use Koha::Database;
use Koha::Biblios;
use Koha::Items;
use Koha::ILL::Requests;
use Koha::Script qw(-cron);

binmode( STDOUT, ':encoding(utf8)' );

my $confirm;
my $limit;
my @illrequest_ids;
my $verbose;
my $help;

my $ok = GetOptions(
    'confirm'      => \$confirm,
    'limit=i'      => \$limit,
    'illrequest=i' => \@illrequest_ids,
    'verbose|v'    => \$verbose,
    'help|h'       => \$help,
);

if ( !$ok || $help ) {
    print_usage();
    exit( $ok ? 0 : 1 );
}

sub print_usage {
    print <<'_USAGE_';

cleanup_duplicate_virtual_records.pl - remove orphan duplicate virtual records ([#223])

    --confirm          Perform the deletions (default is a dry run)
    --limit <n>        Only process the first <n> candidate pairs
    --illrequest <id>  Only process the pair for this ILL request id (repeatable)
    --verbose|-v       Show per-pair detail
    --help|-h          Print this help and exit

_USAGE_
}

my $plugin  = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
my $backend = $plugin->ill_backend();
my $schema  = Koha::Database->new->schema;

# Collect the set of virtual-item notes across all configured pods. Different
# pods may use a different default_checkin_note; we match any of them.
my %notes;
foreach my $pod ( @{ $plugin->pods } ) {
    my $config = $plugin->pod_config($pod) // {};
    my $note   = $config->{default_checkin_note} || 'Additional processing required (ILL)';
    $notes{$note} = 1;
}
$notes{'Additional processing required (ILL)'} = 1;    # always include the default
my @virtual_notes = keys %notes;

my %only_ill = map { $_ => 1 } @illrequest_ids;

print "Mode: " . ( $confirm ? "CONFIRM (records WILL be deleted)" : "DRY RUN (no changes)" ) . "\n";
print "Virtual-item notes matched: " . join( ' | ', map { "'$_'" } @virtual_notes ) . "\n\n";

# Find candidate -N virtual items. We resolve the base barcode as everything
# before the last '-<digits>' and look for a base item carrying a virtual note.
my $items_rs = Koha::Items->search(
    { 'me.itemnotes_nonpublic' => { -in => \@virtual_notes } },
    { order_by                 => 'me.itemnumber' }
);

my $scanned    = 0;
my $candidates = 0;
my $deleted    = 0;
my $skipped    = 0;
my @skips;

while ( my $suffix_item = $items_rs->next ) {
    my $barcode = $suffix_item->barcode // next;

    # Must look like a collision suffix: <base>-<digits>
    next unless $barcode =~ /^(.+)-\d+$/;
    my $base_barcode = $1;

    # Base item must exist AND be a virtual item too (otherwise it's a
    # legitimate collision with a real owned item -> leave it alone).
    # NOTE: use search()->next, not find(): find() can resolve on the unique
    # barcode key alone and ignore the note condition.
    my $base_item = Koha::Items->search(
        {
            barcode             => $base_barcode,
            itemnotes_nonpublic => { -in => \@virtual_notes },
        }
    )->next;
    next unless $base_item;

    $scanned++;

    my $suffix_biblio_id = $suffix_item->biblionumber;
    my $base_biblio_id   = $base_item->biblionumber;

    # The -N biblio should be referenced by exactly one RapidoILL request.
    my $suffix_reqs = Koha::ILL::Requests->search(
        { biblio_id => $suffix_biblio_id, backend => $backend } );
    my $suffix_req_count = $suffix_reqs->count;
    my $suffix_req       = $suffix_reqs->next;

    # The base biblio must NOT be referenced by any ILL request (it's the orphan).
    my $base_ref_count =
        Koha::ILL::Requests->search( { biblio_id => $base_biblio_id } )->count;

    my $reason;
    if ( !$suffix_req ) {
        $reason = "the -N biblio ($suffix_biblio_id) is not referenced by a RapidoILL request";
    } elsif ( $suffix_req_count > 1 ) {
        $reason = "the -N biblio ($suffix_biblio_id) is referenced by more than one ILL request";
    } elsif ($base_ref_count) {
        $reason = "the base biblio ($base_biblio_id) is still referenced by an ILL request";
    } elsif ( $base_item->checkout ) {
        $reason = "the base item is checked out";
    } elsif ( $suffix_item->checkout ) {
        $reason = "the -N item is checked out";
    }

    if ( @illrequest_ids && ( !$suffix_req || !$only_ill{ $suffix_req->id } ) ) {
        next;    # filtered out by --illrequest
    }

    $candidates++;

    my $req_id = $suffix_req ? $suffix_req->id : '(none)';

    if ($reason) {
        $skipped++;
        push @skips,
            sprintf( "  SKIP  base=%s (%s) / suffix=%s (%s) req=%s : %s",
            $base_biblio_id, $base_barcode, $suffix_biblio_id, $barcode, $req_id, $reason );
        next;
    }

    printf(
        "  %s orphan base biblio=%d barcode='%s'  (keeping suffix biblio=%d barcode='%s', ILL request %s)\n",
        ( $confirm ? "DELETE" : "WOULD DELETE" ),
        $base_biblio_id, $base_barcode, $suffix_biblio_id, $barcode, $req_id
    );

    if ($verbose) {
        printf( "        base item=%d  suffix item=%d\n", $base_item->itemnumber, $suffix_item->itemnumber );
    }

    if ($confirm) {
        my $biblio = Koha::Biblios->find($base_biblio_id);
        if ( !$biblio ) {
            print "        ! base biblio vanished, skipping\n";
            next;
        }

        my $error = try {
            my $err;
            $schema->txn_do(
                sub {
                    $err = $plugin->delete_virtual_biblio(
                        {
                            biblio  => $biblio,
                            context => 'cleanup_duplicate_virtual_records',
                        }
                    );
                    die "$err\n" if $err;
                }
            );
            return;
        } catch {
            return $_;
        };

        if ($error) {
            $skipped++;
            chomp $error;
            print "        ! failed to delete base biblio $base_biblio_id: $error\n";
        } else {
            $deleted++;
        }
    }

    last if $limit && $candidates >= $limit;
}

print "\n";
print @skips ? ( join( "\n", @skips ) . "\n\n" ) : ();

print "=" x 60 . "\n";
print "SUMMARY\n";
print "=" x 60 . "\n";
printf( "Suffix virtual items scanned (both sides virtual): %d\n", $scanned );
printf( "Candidate orphan pairs:                            %d\n", $candidates );
if ($confirm) {
    printf( "Orphan biblios deleted:                            %d\n", $deleted );
    printf( "Skipped (safety checks / errors):                  %d\n", $skipped );
} else {
    printf( "Would delete:                                      %d\n", $candidates - $skipped );
    printf( "Skipped (safety checks):                           %d\n", $skipped );
    print "\nRe-run with --confirm to perform the deletions.\n";
}

1;
