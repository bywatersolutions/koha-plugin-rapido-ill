requires 'DBI';
requires 'DateTime';
requires 'Exception::Class';
requires 'File::Slurp';
requires 'HTTP::Request';
requires 'HTTP::Request::Common';
requires 'HTTP::Response';
requires 'JSON';
requires 'List::MoreUtils';
requires 'LWP::UserAgent';
requires 'Modern::Perl';
requires 'Mojo::Base';
requires 'Mojo::JSON';
requires 'Text::Table';
requires 'Try::Tiny';
requires 'URI';
requires 'YAML::XS';

test_requires 'Mojolicious::Lite';
test_requires 'Test::Exception';
test_requires 'Test::MockModule';
test_requires 'Test::MockObject';
test_requires 'Test::Mojo';
test_requires 'Test::NoWarnings';
test_requires 'Test::Warn';

recommends 'DDP';
