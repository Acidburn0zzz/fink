#
# Fink::PkgVersion class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

package Fink::PkgVersion;
use Fink::Base;

use Fink::Services qw(filename expand_percent expand_url execute find_stow latest_version);
use Fink::Package;
use Fink::Config qw($config $basepath);

use strict;
use warnings;

BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  $VERSION = 1.00;
  @ISA         = qw(Exporter Fink::Base);
  @EXPORT      = qw();
  @EXPORT_OK   = qw();  # eg: qw($Var1 %Hashit &func3);
  %EXPORT_TAGS = ( );   # eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }       # module clean-up code here (global destructor)


### self-initialization

sub initialize {
  my $self = shift;
  my ($pkgname, $version, $revision, $source);
  my ($depspec, $deplist, $dep, $expand, $configure_params);
  my ($i);

  $self->SUPER::initialize();

  $self->{_name} = $pkgname = $self->param_default("Package", "");
  $self->{_version} = $version = $self->param_default("Version", "0");
  $self->{_revision} = $revision = $self->param_default("Revision", "0");
  $self->{_type} = lc $self->param_default("Type", "");

  # some commonly used stuff
  $self->{_fullversion} = $version."-".$revision;
  $self->{_fullname} = $pkgname."-".$version."-".$revision;

  # percent-expansions
  $configure_params = "--prefix=\%p ".
    $self->param_default("ConfigureParams", "");
  $expand = { 'n' => $pkgname,
	      'v' => $version,
	      'r' => $revision,
	      'f' => $self->{_fullname},
	      'p' => $basepath,
	      'i' => "$basepath/stow/".$self->{_fullname},
	      'a' => "$basepath/fink/patch",
	      'c' => $configure_params};
  $self->{_expand} = $expand;

  # parse dependencies
  $depspec = $self->param_default("Depends", "");
  $deplist = [];
  foreach $dep (split(/\s*\,\s*/, $depspec)) {
    next if $dep eq "x11";
    push @$deplist, $dep;
  }
  if ($self->param_boolean("UsesGettext")) {
    push @$deplist, "gettext";
  }
  $self->{_depends} = $deplist;

  # expand source
  $source = $self->param_default("Source", "\%n-\%v.tar.gz");
  if ($source eq "gnu") {
    $source = "mirror:gnu:\%n/\%n-\%v.tar.gz";
  } elsif ($source eq "gnome") {
    $source = "mirror:gnome:stable/sources/\%n/\%n-\%v.tar.gz";
  }

  $source = &expand_percent($source, $expand);
  $self->{source} = $source;
  $self->{_sourcecount} = 1;

  for ($i = 2; $self->has_param('source'.$i); $i++) {
    $self->{'source'.$i} = &expand_percent($self->{'source'.$i}, $expand);
    $self->{_sourcecount} = $i;
  }
}

### get package name, version etc.

sub get_name {
  my $self = shift;
  return $self->{_name};
}

sub get_version {
  # return version or version-revision here ?

  my $self = shift;
  return $self->{_version};
}

sub get_onlyversion {
  my $self = shift;
  return $self->{_version};
}

sub get_revision {
  my $self = shift;
  return $self->{_revision};
}

sub get_fullversion {
  my $self = shift;
  return $self->{_fullversion};
}

sub get_fullname {
  my $self = shift;
  return $self->{_fullname};
}

### other accessors

sub is_multisource {
  my $self = shift;
  return $self->{_sourcecount} > 1;
}

sub get_source {
  my $self = shift;
  my $index = shift || 1;
  if ($index < 2) {
    return $self->param("Source");
  } elsif ($index <= $self->{_sourcecount}) {
    return $self->param("Source".$index);
  }
  return "-";
}

sub get_tarball {
  my $self = shift;
  my $index = shift || 1;
  if ($index < 2) {
    return &filename($self->param("Source"));
  } elsif ($index <= $self->{_sourcecount}) {
    return &filename($self->param("Source".$index));
  }
  return "-";
}

sub get_build_directory {
  my $self = shift;
  my ($dir);

  if (exists $self->{_builddir}) {
    return $self->{_builddir};
  }

  if ($self->param_boolean("NoSourceDirectory")) {
    $self->{_builddir} = $self->get_fullname();
    return $self->{_builddir};
  }
  if ($self->has_param("SourceDirectory")) {
    $self->{_builddir} = $self->get_fullname()."/".
      $self->param("SourceDirectory");
    return $self->{_builddir};
  }

  $dir = $self->get_tarball();
  if ($dir =~ /^(.*)\.tar\.(gz|Z|bz2)$/) {
    $dir = $1;
  }
  if ($dir =~ /^(.*)\.tgz$/) {
    $dir = $1;
  }

  $self->{_builddir} = $self->get_fullname()."/".$dir;
  return $self->{_builddir};
}

### get installation state

sub is_fetched {
  my $self = shift;
  my ($i);

  if ($self->{_type} eq "bundle") {
    return 1;
  }

  for ($i = 1; $i <= $self->{_sourcecount}; $i++) {
    if (not defined $self->find_tarball($i)) {
      return 0;
    }
  }
  return 1;
}

sub is_present {
  my $self = shift;
  my ($idir);

  $idir = "$basepath/stow/".$self->get_fullname();

  if (-e "$idir/var/fink-stamp/".$self->get_fullname()) {
    return 1;
  }
  return 0;
}

sub is_installed {
  my $self = shift;

  if (-e "$basepath/var/fink-stamp/".$self->get_fullname()) {
    return 1;
  }
  return 0;
}

### source tarball finding

sub find_tarball {
  my $self = shift;
  my $index = shift || 1;
  my ($archive, $found_archive);
  my (@search_dirs, $search_dir);

  $archive = $self->get_tarball($index);
  if ($archive eq "-") {  # bad index
    return undef;
  }

  # compile list of dirs to search
  @search_dirs = ( "$basepath/src" );
  if ($config->has_param("FetchAltDir")) {
    push @search_dirs, $config->param("FetchAltDir");
  }

  # search for archive
  foreach $search_dir (@search_dirs) {
    $found_archive = "$search_dir/$archive";
    if (-f $found_archive) {
      return $found_archive;
    }
  }
  return undef;
}

### get dependencies

sub get_depends {
  my $self = shift;

  return @{$self->{_depends}};
}


### find package and version by matching a specification

sub match_package {
  shift;  # class method - ignore first parameter
  my $s = shift;
  my $quiet = shift || 0;

  my ($pkgname, $package, $version, $pkgversion);
  my ($found, @parts, $i, @vlist, $v, @rlist);


  # first, search for package
  $found = 0;
  $package = Fink::Package->package_by_name($s);
  if (defined $package) {
    $found = 1;
    $pkgname = $package->get_name();
    $version = "###";
  } else {
    # try to separate version from name (longest match)
    @parts = split(/-/, $s);
    for ($i = $#parts - 1; $i >= 0; $i--) {
      $pkgname = join("-", @parts[0..$i]);
      $version = join("-", @parts[$i+1..$#parts]);
      $package = Fink::Package->package_by_name($pkgname);
      if (defined $package) {
	$found = 1;
	last;
      }
    }
  }
  if (not $found) {
    print "no package found for \"$s\"\n"
      unless $quiet;
    return undef;
  }

  # DEBUG
  print "pkg $pkgname  version $version\n"
    unless $quiet;

  # we now have the package name in $pkgname, the package
  # object in $package, and the
  # still to be matched version (or "###") in $version.
  if ($version eq "###") {
    # find the newest version

    $version = &latest_version($package->list_versions());
    if (defined $version) {
      print "pkg $pkgname  version $version\n"
	unless $quiet;
    } else {
      # there's nothing we can do here...
      die "no version info available for $pkgname\n";
    }
  } elsif (not defined $package->get_version($version)) {
    # try to match the version

    @vlist = $package->list_versions();
    @rlist = ();
    foreach $v (@vlist)  {
      if ($package->get_version($v)->get_onlyversion() eq $version) {
	push @rlist, $v;
      }
    }
    $version = &latest_version(@rlist);
    if (defined $version) {
      print "pkg $pkgname  version $version\n"
	unless $quiet;
    } else {
      # there's nothing we can do here...
      die "no matching version found for $pkgname\n";
    }
  }

  return $package->get_version($version);
}

###
### PHASES
###

### fetch

sub phase_fetch {
  my $self = shift;
  my ($i);

  if ($self->{_type} eq "bundle") {
    return;
  }

  for ($i = 1; $i <= $self->{_sourcecount}; $i++) {
    $self->fetch_source($i);
  }
}

sub fetch_source {
  my $self = shift;
  my $index = shift;
  my ($url, $file);

  chdir "$basepath/src";

  $url = &expand_url($self->get_source($index));
  $file = $self->get_tarball($index);

  if (-f $file) {
    &execute("rm -f $file");
  }
  &execute("wget $url");
  if (not -f $file) {
    die "file download failed for $file\n";
  }
}

### unpack

sub phase_unpack {
  my $self = shift;
  my ($archive, $found_archive, $bdir, $destdir, $tar_cmd);
  my ($i);

  if ($self->{_type} eq "bundle") {
    return;
  }

  $bdir = $self->get_fullname();

  # remove dir if it exists
  chdir "$basepath/src";
  if (-e $bdir) {
    if (&execute("rm -rf $bdir")) {
      die "can't remove existing directory $bdir\n";
    }
  }

  for ($i = 1; $i <= $self->{_sourcecount}; $i++) {
    $archive = $self->get_tarball($i);

    # search for archive, try fetching if not found
    $found_archive = $self->find_tarball($i);
    if (not defined $found_archive) {
      $self->fetch_source($i);
      $found_archive = $self->find_tarball($i);
    }
    if (not defined $found_archive) {
      die "can't find source tarball $archive!\n";
    }

    # determine unpacking command
    $tar_cmd = "tar -xvf $found_archive";
    if ($archive =~ /[\.\-]tar\.(gz|Z)$/ or $archive =~ /\.tgz$/) {
      $tar_cmd = "gzip -dc $found_archive | tar -xvf -";
    } elsif ($archive =~ /[\.\-]tar\.bz2$/) {
      $tar_cmd = "bzip2 -dc $found_archive | tar -xvf -";
    }

    # calculate destination directory
    $destdir = "$basepath/src/$bdir";
    if ($i > 1) {
      if ($self->has_param("Source".$i."ExtractDir")) {
	$destdir .= "/".$self->param("Source".$i."ExtractDir");
      }
    }

    # create directory
    if (&execute("mkdir -p $destdir")) {
      die "can't create directory $destdir\n";
    }

    # unpack it
    chdir $destdir;
    if (&execute($tar_cmd)) {
      die "unpacking failed\n";
    }
  }
}

### patch

sub phase_patch {
  my $self = shift;
  my ($dir, $patch_script, $cmd, $patch);

  if ($self->{_type} eq "bundle") {
    return;
  }

  $dir = $self->get_build_directory();
  chdir "$basepath/src/$dir";

  $patch_script = "";

  ### copy host type scripts (config.guess and config.sub) if required

  if ($self->param_boolean("UpdateConfigGuess")) {
    $patch_script .=
      "cp -f $basepath/fink/update/config.guess .\n".
      "cp -f $basepath/fink/update/config.sub .\n";
  }

  ### copy libtool scripts (ltconfig and ltmain.sh) if required

  if ($self->param_boolean("UpdateLibtool")) {
    $patch_script .=
      "cp -f $basepath/fink/update/ltconfig .\n".
      "cp -f $basepath/fink/update/ltmain.sh .\n";
  }

  ### patches specifies by filename

  if ($self->has_param("Patch")) {
    foreach $patch (split(/\s+/,$self->param("Patch"))) {
      $patch_script .= "patch -p1 <\%a/$patch\n";
    }
  }

  ### any additional commands

  if ($self->has_param("PatchScript")) {
    $patch_script .= $self->param("PatchScript");
  }

  $patch_script = &expand_percent($patch_script, $self->{_expand});

  ### patch

  $self->set_env();
  foreach $cmd (split(/\n/,$patch_script)) {
    next unless $cmd;   # skip empty lines

    if (&execute($cmd)) {
      die "patching failed\n";
    }
  }
}

### compile

sub phase_compile {
  my $self = shift;
  my ($dir, $compile_script, $cmd);

  if ($self->{_type} eq "bundle") {
    return;
  }

  $dir = $self->get_build_directory();
  chdir "$basepath/src/$dir";

  # generate compilation script
  $compile_script =
    "./configure \%c\n".
    "make";
  if ($self->has_param("CompileScript")) {
    $compile_script = $self->param("CompileScript");
  }

  $compile_script = &expand_percent($compile_script, $self->{_expand});

  ### compile

  $self->set_env();
  foreach $cmd (split(/\n/,$compile_script)) {
    next unless $cmd;   # skip empty lines

    if (&execute($cmd)) {
      die "compiling failed\n";
    }
  }
}

### install

sub phase_install {
  my $self = shift;
  my ($dir, $install_script, $cmd, $bdir);

  if ($self->{_type} ne "bundle") {
    $dir = $self->get_build_directory();
    chdir "$basepath/src/$dir";
  }

  # generate installation script

  $install_script = "rm -rf \%i\n".
    "mkdir -p \%i\n";
  if ($self->{_type} ne "bundle") {
    if ($self->has_param("InstallScript")) {
      $install_script .= $self->param("InstallScript");
    } else {
      $install_script .= "make install prefix=\%i";
    }
  }
  $install_script .= "\nmkdir -p \%i/var/fink-stamp".
    "\ntouch \%i/var/fink-stamp/\%f";

  $install_script = &expand_percent($install_script, $self->{_expand});

  ### install

  $self->set_env();
  foreach $cmd (split(/\n/,$install_script)) {
    next unless $cmd;   # skip empty lines

    if (&execute($cmd)) {
      die "installing failed\n";
    }
  }

  ### remove build dir

  $bdir = $self->get_fullname();
  chdir "$basepath/src";
  if (not $config->param_boolean("KeepBuildDir") and -e $bdir) {
    if (&execute("rm -rf $bdir")) {
      die "can't remove build directory $bdir\n";
    }
  }
}

### activate

sub phase_activate {
  my $self = shift;
  my ($dir, $stow);

  $dir = $self->get_fullname();

  chdir "$basepath/stow";
  if (-d $dir) {
    # avoid conflicts for info documentation
    if (-f "$dir/info/dir") {
      &execute("rm -f $dir/info/dir");
    }

    $stow = &find_stow;

    if (&execute("$stow $dir")) {
      die "stow failed\n";
    }
  } else {
    die "Package directory $dir not found unter $basepath/stow!\n";
  }
}

### deactivate

sub phase_deactivate {
  my $self = shift;
  my ($dir, $stow);

  $dir = $self->get_fullname();

  chdir "$basepath/stow";
  if (-d $dir) {
    $stow = &find_stow;

    if (&execute("$stow -D $dir")) {
      die "stow failed\n";
    }
  } else {
    die "Package directory $dir not found unter $basepath/stow!\n";
  }
}

### set environment variables according to spec

sub set_env {
  my $self = shift;
  my ($varname, $s, $expand);
  my %defaults = ( "CPPFLAGS" => "-I\%p/include",
		   "LDFLAGS" => "-L\%p/lib" );

  $expand = $self->{_expand};
  foreach $varname ("CC", "CFLAGS",
		    "CPP", "CPPFLAGS",
		    "CXX", "CXXFLAGS",
		    "LD", "LDFLAGS", "LIBS",
		    "MAKE", "MFLAGS") {
    if ($self->has_param("Set$varname")) {
      $s = $self->param("Set$varname");
      if (exists $defaults{$varname} and
	  not $self->param_boolean("NoSet$varname")) {
	$s .= " ".$defaults{$varname};
      }
      $ENV{$varname} = &expand_percent($s, $expand);
    } else {
      if (exists $defaults{$varname} and
	  not $self->param_boolean("NoSet$varname")) {
	$s = $defaults{$varname};
	$ENV{$varname} = &expand_percent($s, $expand);
      } else {
	delete $ENV{$varname};
      }
    }
  }
}


### EOF
1;
