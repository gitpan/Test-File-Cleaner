use inc::Module::Install;

name          ( 'Test-File-Cleaner'                 );
abstract      ( 'Automatically clean up your filesystem after tests' );
author        ( 'Adam Kennedy<cpan@ali.as>'         );
version_from  ( 'lib/Test/File/Cleaner.pm'    );
license       ( 'perl'                              );

requires      ( 'perl'                 => '5.005'   );
requires      ( 'File::Find::Rule'     => '0.02'    );

build_requires( 'Test::More'           => '0.47'    );
build_requires( 'File::Spec'           => '0.82'    );

auto_install();

&WriteAll;
