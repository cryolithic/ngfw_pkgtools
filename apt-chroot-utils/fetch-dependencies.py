#! /usr/bin/python

import apt, apt_pkg, os.path, re, sys, urllib
import optparse

from lib import aptchroot

TMP_DIR    = '/tmp/foo'

# functions
def parseCommandLineArgs(args):
  usage = "usage: %prog [options] <package> [<package>,...]"

  parser = optparse.OptionParser(usage=usage)
  parser.add_option("-f", "--force-download", dest="forceDownload",
                    action="store_true", default=False,
                    help="Force download of all dependencies" )
  parser.add_option("-d", "--distribution", dest="distribution",
                    action="store", default="nightly",
                    help="Set target distribution" )
  parser.add_option("", "--host", dest="host",
                    action="store", default="10.0.0.105",
                    help="Set Untangle mirror host" )  
  parser.add_option("-r", "--repository", dest="repository",
                    action="store", default="lenny",
                    help="Set target repository" )
  parser.add_option("-l", "--local-packages", dest="localPackages",
                    action="store", default="",
                    help="Set target repository" )
  parser.add_option("-s", "--simulate", dest="simulate",
                    action="store_true", default=False,
                    help="Simulate, but do not download" )
  parser.add_option("-u", "--use-debian-mirros", dest="useDebianMirrors",
                    action="store_true", default=False,
                    help="Simulate, but do not download" )
  parser.add_option("-v", "--verbose", dest="verbose",
                    action="store_true", default=False,
                    help="Verbose" )
  parser.add_option("-m", "--mode", dest="mode",
                    action="store", default="download-dependencies",
                    help="Set mode: 'download-dependencies'(default), 'update-all'" )
  
  options, pkgs = parser.parse_args(args)

  if options.localPackages == "":
    options.localPackages = os.path.join(sys.path[0], '../../upstream_pkgs_%s' % (options.repository))

  if len(args) == 0 and options.mode == 'download-dependencies':
    parser.error("Wrong number of arguments")
    
  return pkgs, options

# main
pkgs, options = parseCommandLineArgs(sys.argv[1:])
sources = '''# backports
#deb http://www.backports.org/debian %s-backports main contrib non-free
# volatile
deb http://volatile.debian.org/debian-volatile %s/volatile main contrib non-free
# mephisto
deb http://%s/public/%s %s main premium upstream\n''' % (options.repository,
                                                         options.repository,
                                                         options.host,
                                                         options.repository,
                                                         options.distribution)

if options.useDebianMirrors:
  sources += '''deb http://http.us.debian.org/debian %s main contrib non-free
deb http://security.debian.org/ %s/updates main contrib non-free''' % (options.repository,
                                                                       options.repository )

# FIXME? provide a command line way to specify pinning
preferences = '''Package: *
Pin: release l=Untangle
Pin-Priority: 900
Package: *
Pin: release o=volatile.debian.org
Pin-Priority: 900
Package: *
Pin: release o=www.backports.org
Pin-Priority: 900
Package: *
Pin: release o=Debian
Pin-Priority: 900\n''' # % (options.distribution,) # options.distribution)

aptchroot.initializeChroot(TMP_DIR, sources, preferences)

lp = aptchroot.LocalPackages(options.localPackages)

if options.mode == 'download-dependencies':
  for arg in pkgs:
    pkg = aptchroot.VersionedPackage(arg)

    deps = pkg.getAllDeps()

    for p in deps:
      try:
        versionedPackage = aptchroot.VersionedPackage(p.name)
#        print "*** ", versionedPackage.name, versionedPackage.version

        if (versionedPackage.isVirtual or versionedPackage.isRequired or versionedPackage.isImportant or versionedPackage.isStandard) and not options.forceDownload:
          if options.verbose:
            print "%s won't be downloaded since --force-download wasn't used." % p.name
          continue

        if not lp.has(versionedPackage):
          print "Package %s is missing" % p.name
        elif lp.has(versionedPackage):
          if versionedPackage.name in pkgs:
            if options.verbose:
              print "Download explicitely requested, but we already have that package"
            continue
          elif not lp.get(versionedPackage).satisfies(p):
            if options.verbose:
              print "Version of %s doesn't satisfy dependency (%s)" % (lp.get(versionedPackage), p)
              print "Downloading new one, but you probably want to remove the older one (%s)" % lp.getByName(p.name)
          else:
            continue
        else:
          continue

        if not options.simulate:
          versionedPackage.download()
          lp.add(versionedPackage)

      except Exception,e:
        print p, type(p), p.name, dir(p)
        raise
  #      sys.exit(1)
    #  else:
    #    print "%s is in the store and satisfies the dependency" % lp.get(versionedPackage)
elif options.mode == 'update-all':
  for pkg in lp.pkgs.itervalues():
    newPkg = aptchroot.VersionedPackage(pkg.name)
    if apt_pkg.VersionCompare(pkg.version, newPkg.version):
      pkgPath = pkg.fileName
      newName = os.path.basename(newPkg.fileName)
      newPath = os.path.join(os.path.dirname(pkgPath), newName)
      print "%s: %s -> %s" % (newPkg.name, pkg.version, newPkg.version)
      os.system("svn rm %s" % (pkgPath,))
      newPkg.download()
      lp.add(newPkg)
      os.system("mv %s %s" % (newName, newPath))
      os.system("svn add %s" % (newPath))

os.system('rm -fr ' + TMP_DIR)
