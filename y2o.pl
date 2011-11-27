#!/cygdrive/c/strawberry/perl/bin/perl

use strict;
use Template;
use Time::localtime;
use Data::Dumper;
use feature 'say';
use Digest::MD5 qw(md5 md5_hex md5_base64);

my $num_args = $#ARGV + 1;
if ($num_args != 1) {
    print "\nUsage: $0 file > import.ofx\n";
    exit;
}


# Rename Yodlee account names to those defined in MS Money.  If the 
# ACCTID in the ofx file matches the "Account number" in MS Money, you
# won't be prompted to match accounts. 
#
# Create an acctMap.properties file with all accounts in the following format:
# <Yodlee Account Name>=<MS Money account number>
my %accountIdMap = ();
my $acctIdMapFile = "acctMap.properties";
open(M, "$acctIdMapFile")
  or warn("Can not open account ID map file: $acctIdMapFile");


while (my $line = <M>) {
    $accountIdMap{$1}=$2 while $line =~ m/(.*)=(.*)/g;
}


my $yodleeCsv = $ARGV[0];

open(F, "$yodleeCsv")
  or die("Can not open input yodleeCsv: $!");



# Skip header
<F>;

# Populates account data to be used in the template into two maps, one 
# for banks, one for credit cards.
my $acctMap = {bank => {}, cc => {}};
while (my $line = <F>) {
    chomp $line;

    # Yodlee transaction amounts include commas when greater than 1,000.  
    # Strip these out before parsing the csv.  When I start having 
    # transaction > 1,000,000, I'll have to handle this!
    $line =~ s/(\d),(\d\d\d)/$1$2/;

    my ($status,$date,$origDesc,$splitType,$category,$currency,$amount,$userDescription,$memo,$classification,$accountAndBankName) = split ',', $line;

    # Yodlee includes the bank and account name in a single line formatted as
    # "BankName - AccountName"
    my ($bankName, $acctName) = split ' - ', $accountAndBankName;
    $bankName =~ s/^\s+//;


    # Yodlee always seems to append CREDIT CARD to the credit card names,
    # so this seems like a reasonable way to distinguish them.
    my $acctCat;
    if ($acctName =~ /CREDIT CARD/) {
        $acctCat = $acctMap->{cc}
    } else {
        $acctCat = $acctMap->{bank}
    }

    # Rename Yodlee account names to those defined in MS Money.  
    my $acctId = $accountIdMap{$acctName};
    if (!$acctId) {
        $acctId = $acctName;
    }

    # Yodlee does not include a unique transaction ID.  Without this,
    # duplicates entries will be added if the same transaction is re-imported.
    # This creates a checksum of the amount, date and description to act
    # as the unique ID.  However, this will also prevent importing two
    # transactions which legitimately have identical values for these fields.
    my $chksum=md5_hex($amount,$date,$origDesc);

    # Strip out quotes from amounts
    $amount =~ s/"//g;

    # Strip out ampersands from descriptions, which seems to confuse MS Money
    $origDesc =~ s/&//g;

    if (!exists($acctCat->{$acctId})) {
        $acctCat->{$acctId} = [];
    }
    my $acct = $acctCat->{$acctId};

    # Put the date in YYYYMMDD format
    $date =~ s#(\d\d)/(\d\d)/(\d\d\d\d)#$3$1$2#;

    # Populate the values to be used to generate the template.
    my $templateValues = {};
    $templateValues->{date}=$date;
    $templateValues->{origDesc}=$origDesc;
    $templateValues->{category}="$category - $classification";
    $templateValues->{currency}=$currency;
    $templateValues->{amount}=$amount;
    $templateValues->{transactionId}=$chksum;
    $templateValues->{bankName}=$bankName;
    $templateValues->{acctId}=$acctId;
    push @$acct, $templateValues;
}
#say Dumper($acctMap);



my $template = Template->new();

# use the current timestamp (number of seconds since Jan 1, 1970) as a unique id
my $trnuid = time;

# Get the current date in YYYYMMDD format
my $tm = localtime;
my $dateStr = sprintf("%04d%02d%02d", $tm->year+1900, 
    ($tm->mon)+1, $tm->mday);

# define template variables for replacement
my $vars = {
    date  => $dateStr,
    trnuid  => $trnuid,
    cc => $acctMap->{cc},
    bank => $acctMap->{bank},
};

# specify input filename, or file handle, text reference, etc.
my $input = 'ofx-template.tt';

# process input template, substituting variables
$template->process($input, $vars)
    || die $template->error();

