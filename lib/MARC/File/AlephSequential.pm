package MARC::File::AlephSequential;

=head1 NAME

MARC::File::AlephSequential - AlephSequential-specific file handling

=cut

our $VERSION = '0.2.1';

use strict;
use integer;

use XML::DOM;
use XML::Writer;
use vars qw( $ERROR );
use MARC::File::Encode qw( marc_to_utf8 );

use MARC::File;
use vars qw( @ISA ); @ISA = qw( MARC::File );

use MARC::Record qw( LEADER_LEN );
use MARC::Field;


# doc id's are generated from this if records are missing 001 -field.
my $doc_id_counter = 1;

=head1 SYNOPSIS

    use MARC::File::AlephSequential;

    my $file = MARC::File::AlephSequential->in( $filename );

    while ( my $marc = $file->next() ) {
        # Do something
    }
    $file->close();
    undef $file;

=head1 EXPORT

None.

=head1 METHODS

=cut

sub _next {
    my $self = shift;
    my $fh = $self->{fh};
    return if eof($fh);

    my $lineId = undef;
    my $id = undef;
    my $record = "";
    my $pos;
    do {
        $pos = $fh->getpos();
        my $line = $fh->getline();
        
        $lineId = substr($line,0,9);
        if (!defined($id)) {
            $id = $lineId;
        }
        
        if ($lineId == $id) {
            $record .= $line;
        }
        
    } while($lineId == $id && !eof($fh));
    
    if (!eof($fh)) {
        $fh->setpos($pos);
    }
    
    return $record;
}

=head2 decode( $string [, \&filter_func ] )

Constructor for handling data from a AlephSequential file.  This function takes care of
all the tag directory parsing & mangling.

Any warnings or coercions can be checked in the C<warnings()> function.

The C<$filter_func> is an optional reference to a user-supplied function
that determines on a tag-by-tag basis if you want the tag passed to it
to be put into the MARC record.  The function is passed the tag number
and the raw tag data, and must return a boolean.  The return of a true
value tells MARC::File::AlephSequential::decode that the tag should get put into
the resulting MARC record.

For example, if you only want title and subject tags in your MARC record,
try this:

    sub filter {
        my ($tagno,$tagdata) = @_;

        return ($tagno == 245) || ($tagno >= 600 && $tagno <= 699);
    }

    my $marc = MARC::File::AlephSequential->decode( $string, \&filter );

Why would you want to do such a thing?  The big reason is that creating
fields is processor-intensive, and if your program is doing read-only
data analysis and needs to be as fast as possible, you can save time by
not creating fields that you'll be ignoring anyway.

Another possible use is if you're only interested in printing certain
tags from the record, then you can filter them when you read from disc
and not have to delete unwanted tags yourself.

=cut

sub decode {

    my $text;
    
    my $location = '';


    my $last_field;
    my $last_subfield;
    my $fieldDef;
    my $append = 0;
    ## decode can be called in a variety of ways
    ## $object->decode( $string )
    ## MARC::File::AlephSequential->decode( $string )
    ## MARC::File::AlephSequential::decode( $string )
    ## this bit of code covers all three

    my $self = shift;
    if ( ref($self) =~ /^MARC::File/ ) {
        $location = 'in record '.$self->{recnum};
        $text = shift;
    } else {
        $location = 'in record 1';
        $text = $self=~/MARC::File/ ? shift : $self;
    }
    
    # Aleph sequential has FMT fields.
    MARC::Field->allow_controlfield_tags('FMT');
     
    my $filter_func = shift;

    # create an empty record which will be filled.
    my $marc = MARC::Record->new();
    
    my @lines = split /\r?\n/, $text;
    
    foreach my $line (@lines) {
        
        if ($line =~ /(\d{9}) (\w{3})(\w|\s{1})(\w|\s{1}) L (.*)/) {
            my $doc_id = $1;
            my $tag = $2;
            my $ind1 = $3;
            my $ind2 = $4;
            my $data = $5;
            my $field;
          
            
            
            if ($tag eq "LDR") {
                $marc->leader($data);
            } elsif (isFixField($tag)) {
                $field = MARC::Field->new($tag, $data);
                $marc->append_fields($field);
            } else {
                
                # Does not parse correctly if field is cut with $9 subfield (where it's longer than 2000 bytes) in decode()
                # if you fix it, change the TODO -list in the end of this file too.
                my @subfields = ();
                my @subfieldRaw = split /\$\$/, $data;
                #subfield data starts with $$, so first element is always empty.
                shift(@subfieldRaw); 

                foreach my $subfield (@subfieldRaw) {
                    
                    my $code = substr($subfield,0,1);
                    my $sub_data = substr($subfield,1);
                    
                    push(@subfields, {
                       'code' => $code,
                       'data' => $sub_data 
                    });
                }
                
                if (defined($fieldDef) && $fieldDef->{'tag'} == $tag && $subfields[0]->{'code'} == 9 && $subfields[0]->{'data'} eq "^^") {
               
                    my $lastSubfield = pop(@{$fieldDef->{'subfields'}});
                    if ($lastSubfield->{'code'} == $subfields[1]->{'code'}) {
                        # is continued subfield
                        # remove circumflex and carriage return from end.
                        # it looks like the fields are broken from spaces, and the space chars will go missing, so adding one.
                        $lastSubfield->{'data'} = substr($lastSubfield->{'data'},0,-2) .' '. $subfields[1]->{'data'}  ;
                        #$lastSubfield->{'data'} = $lastSubfield->{'data'}  . $subfields[1]->{'data'}  ;
                        push(@{$fieldDef->{'subfields'}}, $lastSubfield);
                    } else {
                        
                    }
               
                } else {
                    # Create field and append it to record
                    if (defined($fieldDef)) {
               
                        $marc->append_fields( createFieldFromDef( $fieldDef ));
               
                    }
                    
                    $fieldDef = {
                        'tag' => $tag,
                        'ind1' => $ind1,
                        'ind2' => $ind2,
                        'subfields' => \@subfields
                    }
                
                }
               
            }

        } else {
            print STDERR "Warning: Skipping unrecognized line: $line\n";
        }
        
    }
    # Append last field from $fieldDef buffer
    if (defined($fieldDef)) {
        $marc->append_fields( createFieldFromDef( $fieldDef ));
    }
                 
    return $marc;
}

sub createFieldFromDef {
    
    my $fieldDef = shift;
    my @subfieldListData = ();
    foreach my $subHash (@{$fieldDef->{'subfields'}}) {
        push(@subfieldListData, $subHash->{'code'});
        push(@subfieldListData, $subHash->{'data'});
    }
    

    my $field = MARC::Field->new(
        $fieldDef->{'tag'}, 
        $fieldDef->{'ind1'}, 
        $fieldDef->{'ind2'}, 
        @subfieldListData
    );
    return $field;
}

my %fixFields = (
    '001' => 1,
    '002' => 1,
    '003' => 1,
    '004' => 1,
    '005' => 1,
    '006' => 1,
    '007' => 1,
    '008' => 1,
    '009' => 1,
    'FMT' => 1
);

sub isFixField {
    my $tag = shift;
    
    return $fixFields{$tag} == 1
    
}


=head2 encode()

Returns a string of characters suitable for writing out to a AlephSequential file

=cut

sub encode() {
    my $marc = shift;
    $marc = shift if (ref($marc)||$marc) =~ /^MARC::File/;

    my @fields = ();

    push(@fields, {
       'tag' => "LDR",
       'data' => $marc->leader()
    });
  
	for my $field ($marc->fields()) {
		
		if ($field->is_control_field()) {
            
            push(@fields, {
                'tag' => $field->tag(),
                'i1' => '',
                'i2' => '',
                'data' => $field->data()
            });
			
		} else {
		
            my $data = "";
			for my $subfield ($field->subfields) {
				
                $data .= '$$' . $subfield->[0] . $subfield->[1]
			
			}
            
            push(@fields, {
                'tag' => $field->tag(),
                'i1' => $field->indicator(1),
                'i2' => $field->indicator(2),
                'data' => $data
            });
			
		}
		
	}
    
    my $f001 = $marc->field('001');
    my $doc_id;
    if (defined($f001)) {
        $doc_id = $f001->data();
    } else {
        $doc_id = $doc_id_counter++;
    }
   
    my $doc = "";
	
    # Does not cut fields if their length is more than 2000 chars (or is it bytes?)
    # if you fix it, change the TODO -list in the end of this file too.
    
    foreach my $f (@fields) {
        $doc .= sprintf("%09d", $doc_id) . " ";
        $doc .= sprintf("%-6s", $f->{'tag'} . $f->{'i1'} . $f->{'i2'});
        $doc .= "L ";
        $doc .= $f->{'data'};
        $doc .= "\n";
    }


	return $doc;

}
1;

__END__

=head1 RELATED MODULES

L<MARC::Record>

=head1 TODO

filter func is not implemented in decode.

Does not cut fields if their length is more than 2000 chars in encode() (or is it bytes?)
Does not parse correctly if field is cut with $9 indicator (where it's longer than 200 chars) in decode()


=head1 LICENSE

This code may be distributed under the same terms as Perl itself.

Please note that these modules are not products of or supported by the
employers of the various contributors to the code.

=head1 AUTHOR

Pasi Tuominen, C<< <pasi.e.tuominen@helsinki.fi> >>

=cut

