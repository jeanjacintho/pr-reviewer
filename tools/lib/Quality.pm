package Quality;
# Shared source handling for the quality tools: which files to analyze and
# how to see the code part of a Bash or jq line.
use strict;
use warnings;
use File::Find ();

my %SKIP_DIRS = map { $_ => 1 } qw(.git .claude docs tests tools work state node_modules);

# Relative paths of the project's Bash files (and jq files when asked),
# skipping tests, tools, docs and runtime directories.
sub source_files {
    my ($root, $with_jq) = @_;
    my @found;
    File::Find::find({
        no_chdir => 1,
        preprocess => sub { sort @_ },
        wanted => sub {
            return if $File::Find::name eq $root;
            my $rel = substr($File::Find::name, length($root) + 1);
            if (-d $File::Find::name) {
                $File::Find::prune = 1 if $SKIP_DIRS{(split m{/}, $rel)[-1]};
                return;
            }
            push @found, $rel if is_bash($File::Find::name) || ($with_jq && $rel =~ /\.jq$/);
        },
    }, $root);
    return @found;
}

sub is_bash {
    my ($path) = @_;
    return 1 if $path =~ /\.sh$/;
    return 0 if $path =~ m{/[^/]*\.[^/]*$};
    open my $fh, '<', $path or return 0;
    my $first = <$fh> // '';
    return $first =~ /^#!.*\bbash\b/ ? 1 : 0;
}

sub read_lines {
    my ($path) = @_;
    open my $fh, '<', $path or die "cannot read $path: $!\n";
    my @lines = <$fh>;
    chomp @lines;
    return @lines;
}

# The line with quoted text and trailing comments blanked to spaces, so it
# keeps its length and positions but no string or comment content matches.
sub masked {
    my ($line) = @_;
    my @c = split //, $line;
    my ($quote, $prev) = ('', ' ');
    for (my $i = 0; $i < @c; $i++) {
        my $ch = $c[$i];
        if ($quote eq '') {
            if ($ch eq '\\') { $i++; $prev = ' '; next; }
            if ($ch eq '#' && $prev =~ /[\s;]/) { $c[$_] = ' ' for $i .. $#c; last; }
            $quote = $ch if $ch eq '"' || $ch eq "'";
        } elsif ($ch eq $quote) {
            $quote = '';
        } elsif ($quote eq '"' && $ch eq '\\') {
            $c[$i] = ' ';
            $c[$i + 1] = ' ' if $i + 1 < @c;
            $i++;
        } else {
            $c[$i] = ' ';
        }
        $prev = $ch;
    }
    return join '', @c;
}

# One flag per line: 1 for code, 0 for heredoc bodies and their terminators.
sub code_flags {
    my (@lines) = @_;
    my @flags;
    my $delim;
    for my $line (@lines) {
        if (defined $delim) {
            push @flags, 0;
            undef $delim if $line =~ /^\t*\Q$delim\E\s*$/;
            next;
        }
        push @flags, 1;
        $delim = $1 if $line =~ /(?<!<)<<-?\s*['"]?(\w+)['"]?/;
    }
    return @flags;
}

1;
