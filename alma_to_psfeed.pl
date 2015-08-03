#!/usr/bin/perl

#--------------------------------------------------------------
# Read invoice data output from Alma and format into file
# for feed to PeopleSoft.
#
#!/usr/bin/perl

#--------------------------------------------------------------
# Read invoice data output from Alma and format into file
# for feed to PeopleSoft.
#
# Boston College, 2/28/2013
#--------------------------------------------------------------

use POSIX;
use XML::XPath;
use XML::XPath::XMLParser;
use Net::FTP;
use Net::FTP::File;
use MIME::Lite;

($my_day, $my_mon, $my_year) = (localtime) [3,4,5];
#$my_day = 23;
$pt_day = sprintf("%02d", $my_day);
$my_year += 1900;
$my_mon += 1;
$my_date = sprintf("%s%02d%02d", $my_year, $my_mon, $my_day);
$word_month = get_mon_component($my_mon);
$have_file = 0;

#For testing or re-loading set to 1
$skip_ftp = 0;

if (!$skip_ftp)
{ 
     #FTP the file from server
     if ($r_ftp = Net::FTP->new("someserver.bc.edu", Debug => 0))
     {
          if ($r_ftp->login("username", "password"))
          {
	       $r_ftp->binary;
               if ($r_ftp->cwd("/some/directory/psfeed"))
	       {
                    @ps_files = $r_ftp->dir;
                    $no_files = @ps_files;
                    #Skip first file returned - this is dir size
                    for ($i = 1; $i <= $no_files; $i++)
                    {
		         @ps_entry = split(/ /, $ps_files[$i]);
                         $no_parts = @ps_entry;
                  
                         $f_mon = $ps_entry[$no_parts - 4];
                         $f_day = $ps_entry[$no_parts - 3];
 
                         if ( ($word_month eq $f_mon) && ($pt_day eq $f_day) )
                         {
                              $in_fn = $ps_entry[$no_parts - 1];  
                              $ps_fn = $r_ftp->get($in_fn);
                              $have_file = 1;
                              #move the file to the psfeed_sent directory
                              $r_ftp->move($in_fn, "../psfeed_sent/$in_fn");
                              last;
                         }
                    }
	       }
          }

          $r_ftp->quit;
     }
}

#For testing - uncomment out next 2 lines and enter file name to test
#$in_fn = "alma_inv_20130406.xml";
#$have_file = 1;

$no_sent = 0;

#Open output log
$out_fn = sprintf ("%s%s%s", "inv", $my_date, ".log");
$ret = open(OUT_LOG, ">$out_fn");
if ($ret < 1)
{
     die ("Cannot open log file $out_fn");
}

if ($have_file)
{

     $xp = XML::XPath->new(filename=>$in_fn);



     #Open file for feed data going into PeopleSoft
     $feed_fn = sprintf("%s%s%s", "inv", $my_date, "_feed");
     $ret = open(FEED, ">$feed_fn");
     if ($ret < 1)
     {
          die ("Cannot open output file $feed_fn");
     }

     #$nodeset = $xp->find('/notification_data/invoice_list/invoice');
     $nodeset = $xp->find('/notification_data/org_invoice_list/invoice');
     foreach my $node ($nodeset->get_nodelist) 
     {
          #Go process this entire invoice
          &process_invoice($node);
     }

     close (FEED);

}

if ($no_sent > 0)
{
     #Copy the file into the file that needs to be FTP'd to the PeopleSoft server
     @cpylist = ("cp", $feed_fn, "libvchr.txt");
     system(@cpylist);

     $ftp = ps_connection();
     #When testing set ftp to 0
     #$ftp = 0;
     if ($ftp)
     {
          $ps_out_file = "libvchr.txt";
          if ($ftp->put($ps_out_file))
          {
               print OUT_LOG ("\nAlma File ftp'd to the PeopleSoft server successfully: $feed_fn as libvchr.txt");
          }
          else
          {
               print OUT_LOG ("\nUnable to FTP the Alma feed file to the PeopleSoft server $feed_fn as libvchr.txt");
          }

     }
     else
     {
          print OUT_LOG ("\nUnable to ftp Alma file to the PeopleSoft server: $feed_fn as libvchr.txt");
     }

     $ftp->quit;
}
else
{
     print OUT_LOG ("\nFile is empty. Alma File was not FTP'd to PeopleSoft server.\n");
}

close (OUT_LOG);

#Email the log file
send_log ($out_fn);

exit;

sub process_invoice
{
     my ($invoice) = @_;

     $endowment = 0;
     $vrow_id = sprintf("%03d", 0);
     $vlrow_id = sprintf("%03d", 1);
     $dlrow_id = sprintf("%03d", 2);

     @obj_code = ("64801", "64802", "64803", "64804", "64805", "64806", "64807", "64808", "64809", "64810", "64811", "64812", "64813", "64814", "64815", "64816", "64817", "64818", "64819", "64820");
     @obj_desc = ("Print Monographs", "Print Serials", "Film & Video Materials", "Electronic Serials", "Database & Serial Backfile Purchases; One Time Literature Collections", 
             "Kits", "Rare Monographs & Serials", "Archives & Manuscripts", "Graphic Materials", "Online Services", "Electronic Resource Access Fees", "Audio Materials", "Microform Serials", 
             "Electronic Monographs", "Microform Monographs", "Computer files (Locally Held)", "Miscellaneous Material Procurement Fees", "Three Dimensional or Naturally Occurring Material", 
             "Cartographic Material", "Document Delivery & E-Archiving");


     my @chart_str, @ext_budget, @funds, @reporting_codes, @amts_budget;
     my @dist_budget, @dist_rc, @dist_amts, $dist_count;

     undef @chart_str;
     undef @ext_budget;
     undef @funds;
     undef @reporting_codes;
     undef @amts_budget;
     undef @dist_budget;
     undef @dist_rc;
     undef @dist_amts;

     #Get the invoice number
     $inv_no = $invoice->findvalue( './invoice_number');
     #Get the vendor code
     $vendor_code = $invoice->findvalue( './vendor/name');
     #Get the invoice date
     $inv_date = $invoice->findvalue( './invoice_date');
     #Format the date as yyyy/mm/dd from mm/dd/yyyy
     $sub_yr = substr($inv_date, 6, 4);
     $sub_mo = substr($inv_date, 0, 2);
     $sub_dy = substr($inv_date, 3, 2);

     $inv_date = sprintf("%s%s%s%s%s", $sub_yr, "/", $sub_mo, "/", $sub_dy);

     #Verify that invoice year is equal to this year or 1 year less or 1 year greater. If not report error and don't send to PeopleSoft
     if ($sub_yr != $my_year && ($sub_yr != ($my_year - 1)) && ($sub_yr != ($my_year + 1)) )
     {
          print OUT_LOG ("\nInvoice year $sub_yr is questionable for vendor $vendor_code, invoice $inv_no. Please verify date, Record not sent to PeopleSoft\n");
          return;
     }

     #Get the additional code
     $add_code = $invoice->findvalue( './vendor/additional_code');
     @v2 = split (/-/, $add_code);
     $ps_vendor = $v2[0];
     $ps_addrr = $v2[1];

     $len = length($ps_vendor);
     if ($len != 10)
     {
         print OUT_LOG ("\nPeopleSoft Vendor ID $ps_vendor must be 10 digits long for vendor $vendor_code, invoice $inv_no\n");
         return;
     }

     $i = $ps_vendor !~ /[0-9]/;
     if ($i)
     {
          print OUT_LOG ("\nPeopleSoft Vendor ID $ps_vendor must contain 10 digits for vendor $vendor_code, invoice $inv_no\n");
          return;
     }


     $len = length($ps_addrr);
     if ($len > 3)
     {
          print OUT_LOG ("\nPeopleSoft Address ID $ps_addrr must be 1 to 3 digits long for vendor $vendor_code, invoice $inv_no\n");
          return;
     }


     $i = $ps_addrr !~ /[0-9]/;
     if ($i)
     {
          print OUT_LOG ("\nPeopleSoft Address ID $ps_addrr must contain 1-3 digits for vendor $vendor_code, invoice $inv_no\n");
          return;
     }

     $ps_addr = sprintf("%03d", $ps_addrr);

     #Get the discount amount
     $inv_disc = $invoice->findvalue( './discount_amount');
     $len = length($inv_disc);
     @v1 = split(/\./, $inv_disc);
     if ($v1[0] <= 0 && $len <= 3)
     {
	  $inv_disc = "000";
     }
     $inv_discc = &format_ps_money($inv_disc);

     #Get the total amount paid on this invoice
     $inv_tot_amt = $invoice->findvalue( './invoice_total/sum')->value();
     #See if this invoice is for a credit
     $c_or_d = substr($inv_tot_amt, 0, 1);
     if ($c_or_d eq '-')
     {
           print OUT_LOG ("\nInvoice is for a credit for vendor $vendor_code, invoice $inv_no\n");
	   return;
     }

     $inv_tot = sprintf("%.2f", $inv_tot_amt);
     $inv_tott = &format_ps_money($inv_tot);

     #The PS IT folks need to let me know what user_vhchr_dec should be. For now, set the amount to 0 according to Sanjay
     $i = "000";
     $user_vchr_dec = &format_ps_money($i);

     #Grab the chart string(s)
     $i = 0;
     foreach my $ext_d ($invoice->findnodes('./funds_list/fund_ledger_interpreter'))
     {
	  $endowment = 0;

          $ext_budget[$i] = $ext_d->findvalue( './external_d');
          #print ("\nChart String: $ext_budget[$i]");
          $fund_name = $ext_d->findvalue( './name');
          #print ("\nFund Name: $fund_name");
          $funds[$i] = $ext_d->findvalue( './code');

	  @chart_str = split (/-/, $ext_budget[$i]);

          #Validate chart string
          if ($chart_str[0] != '060021' && $chart_str[0] != '060081' && $chart_str[0] != '060001' && $chart_str[0] != '060121' && $chart_str[0] != '060041')
          {
               print OUT_LOG ("\nDepartment $chart_str[0] is invalid for budget number $budget_no invoice $inv_no\n");
               return;
          }
          else #Look for endowments
          {
               if ($chart_str[0] == '060001')
               {
	            $endowment = 1;
               }

	  }

          $i++;
     }

     #Grab the invoice lines
     foreach my $ilines ($invoice->findnodes('./invoice_lines/invoice_line'))
     {
          $inv_line_no = $ilines->findvalue( './invoice_line_number');
          $budget_code = $ilines->findvalue( './reporting_code');

          #Get amount(s) and fund(s) used to pay this invoice line
          foreach my $iline_amt ($ilines->findnodes('./fund_data/fund_short_data'))
          {
               #If going to do math on the value then do findvalue->value() or get a no method found error
               $il_amt = $iline_amt->findvalue( './amount/sum')->value();
               $amt = sprintf("%.2f", $il_amt);

               $fund_code = $iline_amt->findvalue( './fund_code');

               #print ("\nInv Line No: $inv_line_no\n");
               #print ("Obj_code: $budget_code\n");
               #print ("Amount: $amt\n");
               #print ("Fund Code: $fund_code\n");

               #Validate the object (budget) code. If its missing throw it back.
               if ($budget_code ne "64801" && $budget_code ne "64802" && $budget_code ne "64803" && $budget_code ne "64804" && $budget_code ne "64805" && $budget_code ne "64806" &&
                   $budget_code ne "64807" && $budget_code ne "64808" && $budget_code ne "64809" && $budget_code ne "64810" && $budget_code ne "64811" && $budget_code ne "64812" &&
                   $budget_code ne "64813" && $budget_code ne "64814" && $budget_code ne "64815" && $budget_code ne "64816" && $budget_code ne "64817" && $budget_code ne "64818" &&
                   $budget_code ne "64819" && $budget_code ne "64820")
               {
                    print OUT_LOG ("\nObject code missing or invalid for invoice $inv_no line number $inv_line_no. Please resolve.\n");
                    return;
               }

               for ($j = 0; $j < $i; $j++)
               {
                    if ($funds[$j] eq $fund_code)
                    { 
			if ($amts_budget[$j] > 0)
                        {
			     $amts_budget[$j] = $amts_budget[$j] + $amt;
                        }
                        else
                        {
			     $amts_budget[$j] = $amt;
                        }

                        $len = length($budget_code);
                        if ($len > 0)
                        {
                             $reporting_codes[$j] = $budget_code;
                        }
                    }
               }                  

          }
     }

     #Set up the object code description for the voucher line. This only gets sent once per invoice so just grab last one if more than one invoice line
     if ($i > 0)
     {
	  $j = $i - 1;
     }
     else
     {
	  $j = 0;
     }

     for ($k = 0; $k <= $#obj_code; $k++)
     {
          if ($reporting_codes[$j] eq $obj_code[$k])
          {
               $desc = sprintf("%-30s", $obj_desc[$k]);
          }
     }

     #Make sure all of the budget lines add up to the invoice total. 
     for ($j = 0, $tot_iline_amts = 0; $j <= $i; $j++)
     {
           $tot_iline_amts = $tot_iline_amts + $amts_budget[$j];                            
     }

     $tot_line_amts = sprintf("%.2f", $tot_iline_amts);

     if ($tot_line_amts != $inv_tot)
     {
           #Keep these in for testing. If off, by how much?
           if ($tot_line_amts > $inv_tot)
           {
	        $dff = $tot_line_amts - $inv_tot;
           }

           if ($tot_line_amts < $inv_tot)
           {
	        $dff = $inv_tot - $tot_line_amts;
           }

           print OUT_LOG ("\nBudget line amounts do not equal invoice total for invoice $vendor_code $inv_no\n");
           return;
     }

     #Build distribution lines. If chart string (ext_budget) or reporting code changes need a new line
     for ($j = 0, $dist_count = 0; $j < $i; $j++)
     {
          if ($dist_budget[$j] eq $ext_budget[$j] && $dist_rc[$j] eq $reporting_codes[$j])
          { 
	       if ($dist_amts[$j] > 0)
               {
	            $dist_amts[$j] = $dist_amts[$j] + $amts_budget[$j];
               }
               else
               {
	            $dist_amts[$j] = $amts_budget[$j];
               }
          }
          else
          {
              if ($dist_count == 0)
              {
	           $dist_budget[$dist_count] = $ext_budget[$j];
	           $dist_rc[$dist_count] = $reporting_codes[$j];
	           $dist_amts[$dist_count] = $amts_budget[$j];
                   $dist_count++;
              }
              else
              {
	           for ($k = 0, $found_it = 0; $k < $dist_count; $k++)
                   {
                        if ($dist_budget[$k] eq $ext_budget[$j] && $dist_rc[$k] eq $reporting_codes[$j])
                        {
	                     if ($dist_amts[$k] > 0)
                             {
	                          $dist_amts[$k] = $dist_amts[$k] + $amts_budget[$j];
                                  $found_it = 1;
                                  $k = $dist_count; #Break out of this loop
                             }
                             else
                             {
	                          $dist_amts[$k] = $amts_budget[$j];
                                  $found_it = 1;
                                  $k = $dist_count; #Break out of this loop
                             }
                        }
                   }
                   
                   if (!$found_it)
                   {
	                 $dist_budget[$dist_count] = $ext_budget[$j];
	                 $dist_rc[$dist_count] = $reporting_codes[$j];
	                 $dist_amts[$dist_count] = $amts_budget[$j];
                         $dist_count++;
                   }
	      }
          }
     }

     #Build the voucher header
     $vhdr = sprintf("%s%s%s%-30s%s%s%s%03d%s%s%s%s", $vrow_id, "EAGLE", "        ", $inv_no, $inv_date, $ps_vendor, "          ", $ps_addr, "00   ", $inv_tott, $inv_discc, "LIB");
     #print ("\nVoucher Header: $vhdr");
     print FEED ("$vhdr\n");

     #Build the voucher line
     $vline = sprintf("%s%s%s%s%s%s", $vlrow_id, "EAGLE", $inv_tott, "00001", $user_vchr_dec, $desc);
     #print ("\nVoucher Line:   $vline");
     print FEED ("$vline\n");

     #Print the distribution lines
     for ($j = 0; $j < $dist_count; $j++)
     {
          $inv_tott = &format_ps_money($dist_amts[$j]);

	  @chart_str = split (/-/, $dist_budget[$j]);
          $dept = sprintf("%-10s", $chart_str[0]); 
          $fund_code = sprintf ("%-5s", $chart_str[1]);
          $fund_src = sprintf ("%-10s", $chart_str[2]);
          $prog_code = sprintf ("%-5s", $chart_str[3]);
          $ps_func = sprintf ("%-10s", $chart_str[4]);
          $prop = "00000     ";

          #Distribution lines are numbered 1 to n so add 1 to j here.
	  $dline = sprintf("%s%s%s%05d%s%s%s%s%s%s%-10s%s", $dlrow_id, "EAGLE", "00001", ($j+1), $fund_code, $fund_src, $dept, $prog_code, $prop, $ps_func, $dist_rc[$j], $inv_tott);
          #print ("\n$dline"); 
          print FEED ("$dline\n");
     }

     $no_sent++;

     return;
}


#This subroutine formats the money going into the peoplesoft feed into a signed 28 char string with 3 decimal places
#Example: -00000000000000000000123.600 is the amount $123.60
sub format_ps_money
{

    my ($amt) = @_;

    my (@v1, $dpart, $cpart1, $cpart, $len, $ret_amt);

    @v1 = split(/\./, $amt);

    $dpart = $v1[0];
    $cpart = $v1[1];

    $len = length($dpart);
    if ($len <= 0)
    {
	$dpart = 0;
    }

    $len = length($cpart);
    if ($len <= 0)
    {
	$cpart1 = 0;
        $cpart = sprintf("%03d", $cpart1);
    }
    elsif ($len == 1)
    {
	$cpart1 = $cpart;
        $cpart = sprintf("%s%s", $cpart1, "00");
    }
    elsif ($len == 2)
    {
	$cpart1 = $cpart;
        $cpart = sprintf("%s%s", $cpart1, "0");
    }
    
    $ret_amt = sprintf("%024d%s%s", $dpart, ".", $cpart);

    return ($ret_amt);

}


sub ps_connection
{
     my ($ftp);

     #FTP to PeopleSoft production server
     if ($ftp = Net::FTP->new("someserver.bc.edu", Debug => 0))
     {
          if ($ftp->login("username", "password"))
          {
               $ftp->binary;
               if ($ftp->cwd("Library"))
               {
                    return($ftp);
	       }
          }
     }

     $ftp->quit;
}

sub send_log
{
     my($logfn) = @_;

     $email_sender = "Boston College Library";
     $email_subject = "Log: Alma Invoice feed to PeopleSoft";
     $recipient = "you\@unversity.edu";

     #Open output log 
     $ret = open(LOG_IN, $logfn);
     if ($ret < 1)
     {
          die ("Cannot open log file $logfn");
          exit;
     }

     @msg_text = <LOG_IN>;

     $msg = MIME::Lite->new(
                           From => "$email_sender",
                           To => "$recipient",
                           Subject => "$email_subject",
                           Datestamp => 'true',
                           Date => "",
                           Data => "@msg_text"
                           );
     $msg->send;
}

#Convert the month (mm) to a 3 char mon
#Where mon is jan, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec
sub get_mon_component
{
   
    my ($dmon) = @_;

    if ($dmon eq "1")
    {
	$wd_mon = "Jan";
    }
    elsif ($dmon eq "2")
    {
	$wd_mon = "Feb";
    }
    elsif ($dmon eq "3")
    {
	$wd_mon = "Mar";
    }
    elsif ($dmon eq "4")
    {
	$wd_mon = "Apr";
    }
    elsif ($dmon eq "5")
    {
	$wd_mon = "May";
    }
    elsif ($dmon eq "6")
    {
	$wd_mon = "Jun";
    }
    elsif ($dmon eq "7")
    {
	$wd_mon = "Jul";
    }
    elsif ($dmon eq "8")
    {
	$wd_mon = "Aug";
    }
    elsif ($dmon eq "9")
    {
	$wd_mon = "Sep";
    }
    elsif ($dmon eq "10")
    {
	$wd_mon = "Oct";
    }
    elsif ($dmon eq "11")
    {
	$wd_mon = "Nov";
    }
    elsif ($dmon eq "12")
    {
	$wd_mon = "Dec";
    }
    else
    {
        $wd_mon = "error";
    }

    return ($wd_mon);   
}
#
# 2/28/2013
#--------------------------------------------------------------

use POSIX;
use XML::XPath;
use XML::XPath::XMLParser;
use Net::FTP;
use Net::FTP::File;
use MIME::Lite;

($my_day, $my_mon, $my_year) = (localtime) [3,4,5];
#$my_day = 23;
$pt_day = sprintf("%02d", $my_day);
$my_year += 1900;
$my_mon += 1;
$my_date = sprintf("%s%02d%02d", $my_year, $my_mon, $my_day);
$word_month = get_mon_component($my_mon);
$have_file = 0;

#For testing or re-loading set to 1
$skip_ftp = 0;

if (!$skip_ftp)
{ 
     #FTP the file from server
     if ($r_ftp = Net::FTP->new("someserver.bc.edu", Debug => 0))
     {
          if ($r_ftp->login("username", "password"))
          {
	       $r_ftp->binary;
               if ($r_ftp->cwd("/some/directory/psfeed"))
	       {
                    @ps_files = $r_ftp->dir;
                    $no_files = @ps_files;
                    #Skip first file returned - this is dir size
                    for ($i = 1; $i <= $no_files; $i++)
                    {
		         @ps_entry = split(/ /, $ps_files[$i]);
                         $no_parts = @ps_entry;
                  
                         $f_mon = $ps_entry[$no_parts - 4];
                         $f_day = $ps_entry[$no_parts - 3];
 
                         if ( ($word_month eq $f_mon) && ($pt_day eq $f_day) )
                         {
                              $in_fn = $ps_entry[$no_parts - 1];  
                              $ps_fn = $r_ftp->get($in_fn);
                              $have_file = 1;
                              #move the file to the psfeed_sent directory
                              $r_ftp->move($in_fn, "../psfeed_sent/$in_fn");
                              last;
                         }
                    }
	       }
          }

          $r_ftp->quit;
     }
}

#For testing - uncomment out next 2 lines and enter file name to test
#$in_fn = "alma_inv_20130406.xml";
#$have_file = 1;

$no_sent = 0;

#Open output log
$out_fn = sprintf ("%s%s%s", "inv", $my_date, ".log");
$ret = open(OUT_LOG, ">$out_fn");
if ($ret < 1)
{
     die ("Cannot open log file $out_fn");
}

if ($have_file)
{

     $xp = XML::XPath->new(filename=>$in_fn);



     #Open file for feed data going into PeopleSoft
     $feed_fn = sprintf("%s%s%s", "inv", $my_date, "_feed");
     $ret = open(FEED, ">$feed_fn");
     if ($ret < 1)
     {
          die ("Cannot open output file $feed_fn");
     }

     #$nodeset = $xp->find('/notification_data/invoice_list/invoice');
     $nodeset = $xp->find('/notification_data/org_invoice_list/invoice');
     foreach my $node ($nodeset->get_nodelist) 
     {
          #Go process this entire invoice
          &process_invoice($node);
     }

     close (FEED);

}

if ($no_sent > 0)
{
     #Copy the file into the file that needs to be FTP'd to the PeopleSoft server
     @cpylist = ("cp", $feed_fn, "libvchr.txt");
     system(@cpylist);

     $ftp = ps_connection();
     #When testing set ftp to 0
     #$ftp = 0;
     if ($ftp)
     {
          $ps_out_file = "libvchr.txt";
          if ($ftp->put($ps_out_file))
          {
               print OUT_LOG ("\nAlma File ftp'd to the PeopleSoft server successfully: $feed_fn as libvchr.txt");
          }
          else
          {
               print OUT_LOG ("\nUnable to FTP the Alma feed file to the PeopleSoft server $feed_fn as libvchr.txt");
          }

     }
     else
     {
          print OUT_LOG ("\nUnable to ftp Alma file to the PeopleSoft server: $feed_fn as libvchr.txt");
     }

     $ftp->quit;
}
else
{
     print OUT_LOG ("\nFile is empty. Alma File was not FTP'd to PeopleSoft server.\n");
}

close (OUT_LOG);

#Email the log file
send_log ($out_fn);

exit;

sub process_invoice
{
     my ($invoice) = @_;

     $endowment = 0;
     $vrow_id = sprintf("%03d", 0);
     $vlrow_id = sprintf("%03d", 1);
     $dlrow_id = sprintf("%03d", 2);

     @obj_code = ("64801", "64802", "64803", "64804", "64805", "64806", "64807", "64808", "64809", "64810", "64811", "64812", "64813", "64814", "64815", "64816", "64817", "64818", "64819", "64820");
     @obj_desc = ("Print Monographs", "Print Serials", "Film & Video Materials", "Electronic Serials", "Database & Serial Backfile Purchases; One Time Literature Collections", 
             "Kits", "Rare Monographs & Serials", "Archives & Manuscripts", "Graphic Materials", "Online Services", "Electronic Resource Access Fees", "Audio Materials", "Microform Serials", 
             "Electronic Monographs", "Microform Monographs", "Computer files (Locally Held)", "Miscellaneous Material Procurement Fees", "Three Dimensional or Naturally Occurring Material", 
             "Cartographic Material", "Document Delivery & E-Archiving");


     my @chart_str, @ext_budget, @funds, @reporting_codes, @amts_budget;
     my @dist_budget, @dist_rc, @dist_amts, $dist_count;

     undef @chart_str;
     undef @ext_budget;
     undef @funds;
     undef @reporting_codes;
     undef @amts_budget;
     undef @dist_budget;
     undef @dist_rc;
     undef @dist_amts;

     #Get the invoice number
     $inv_no = $invoice->findvalue( './invoice_number');
     #Get the vendor code
     $vendor_code = $invoice->findvalue( './vendor/name');
     #Get the invoice date
     $inv_date = $invoice->findvalue( './invoice_date');
     #Format the date as yyyy/mm/dd from mm/dd/yyyy
     $sub_yr = substr($inv_date, 6, 4);
     $sub_mo = substr($inv_date, 0, 2);
     $sub_dy = substr($inv_date, 3, 2);

     $inv_date = sprintf("%s%s%s%s%s", $sub_yr, "/", $sub_mo, "/", $sub_dy);

     #Verify that invoice year is equal to this year or 1 year less or 1 year greater. If not report error and don't send to PeopleSoft
     if ($sub_yr != $my_year && ($sub_yr != ($my_year - 1)) && ($sub_yr != ($my_year + 1)) )
     {
          print OUT_LOG ("\nInvoice year $sub_yr is questionable for vendor $vendor_code, invoice $inv_no. Please verify date, Record not sent to PeopleSoft\n");
          return;
     }

     #Get the additional code
     $add_code = $invoice->findvalue( './vendor/additional_code');
     @v2 = split (/-/, $add_code);
     $ps_vendor = $v2[0];
     $ps_addrr = $v2[1];

     $len = length($ps_vendor);
     if ($len != 10)
     {
         print OUT_LOG ("\nPeopleSoft Vendor ID $ps_vendor must be 10 digits long for vendor $vendor_code, invoice $inv_no\n");
         return;
     }

     $i = $ps_vendor !~ /[0-9]/;
     if ($i)
     {
          print OUT_LOG ("\nPeopleSoft Vendor ID $ps_vendor must contain 10 digits for vendor $vendor_code, invoice $inv_no\n");
          return;
     }


     $len = length($ps_addrr);
     if ($len > 3)
     {
          print OUT_LOG ("\nPeopleSoft Address ID $ps_addrr must be 1 to 3 digits long for vendor $vendor_code, invoice $inv_no\n");
          return;
     }


     $i = $ps_addrr !~ /[0-9]/;
     if ($i)
     {
          print OUT_LOG ("\nPeopleSoft Address ID $ps_addrr must contain 1-3 digits for vendor $vendor_code, invoice $inv_no\n");
          return;
     }

     $ps_addr = sprintf("%03d", $ps_addrr);

     #Get the discount amount
     $inv_disc = $invoice->findvalue( './discount_amount');
     $len = length($inv_disc);
     @v1 = split(/\./, $inv_disc);
     if ($v1[0] <= 0 && $len <= 3)
     {
	  $inv_disc = "000";
     }
     $inv_discc = &format_ps_money($inv_disc);

     #Get the total amount paid on this invoice
     $inv_tot_amt = $invoice->findvalue( './invoice_total/sum')->value();
     #See if this invoice is for a credit
     $c_or_d = substr($inv_tot_amt, 0, 1);
     if ($c_or_d eq '-')
     {
           print OUT_LOG ("\nInvoice is for a credit for vendor $vendor_code, invoice $inv_no\n");
	   return;
     }

     $inv_tot = sprintf("%.2f", $inv_tot_amt);
     $inv_tott = &format_ps_money($inv_tot);

     #The PS IT folks need to let me know what user_vhchr_dec should be. For now, set the amount to 0 according to Sanjay
     $i = "000";
     $user_vchr_dec = &format_ps_money($i);

     #Grab the chart string(s)
     $i = 0;
     foreach my $ext_d ($invoice->findnodes('./funds_list/fund_ledger_interpreter'))
     {
	  $endowment = 0;

          $ext_budget[$i] = $ext_d->findvalue( './external_d');
          #print ("\nChart String: $ext_budget[$i]");
          $fund_name = $ext_d->findvalue( './name');
          #print ("\nFund Name: $fund_name");
          $funds[$i] = $ext_d->findvalue( './code');

          if ($ext_budget[$i] eq "Law Library")
          {
               print OUT_LOG ("\nLaw Library Invoice $inv_no skipped.\n");
               return;
          }

          
	  @chart_str = split (/-/, $ext_budget[$i]);

          #Validate chart string
          if ($chart_str[0] != '060021' && $chart_str[0] != '060081' && $chart_str[0] != '060001' && $chart_str[0] != '060121' && $chart_str[0] != '060041')
          {
               print OUT_LOG ("\nDepartment $chart_str[0] is invalid for budget number $budget_no invoice $inv_no\n");
               return;
          }
          else #Look for endowments
          {
               if ($chart_str[0] == '060001')
               {
	            $endowment = 1;
               }

               #Check for Social Work endowments
               if ($chart_str[0] == '060081' && $chart_str[1] == '600' && $chart_str[2] == '30730' && $chart_str[4] == '202')
               {
	            $endowment = 1;
               }

               #Check for Burns endowments
               if ($chart_str[0] == '060041' && ($chart_str[1] == '600' || $chart_str[1] == '200' || $char_str[1] == '220'))
               {
                    $endowment = 1;
               }

               #Validate the chart string
               if ($endowment == 1 && ($chart_str[1] != '600' && $chart_str[1] != '200' && $chart_str[1] != '220') )
               {
                    print OUT_LOG ("\nFund Code $chart_str[1] is invalid for fund $fund_name, invoice $vendor_code $inv_no\n");
                    return;
               }
               elsif ($endowment == 0 && $chart_str[1] != '100')
               {
                    print OUT_LOG ("\nFund Code $chart_str[1] is invalid for fund $fund_name, invoice $vendor_code $inv_no\n");
                    return;
               }
	  }

          $i++;
     }

     #Grab the invoice lines
     foreach my $ilines ($invoice->findnodes('./invoice_lines/invoice_line'))
     {
          $inv_line_no = $ilines->findvalue( './invoice_line_number');
          $budget_code = $ilines->findvalue( './reporting_code');

          #Get amount(s) and fund(s) used to pay this invoice line
          foreach my $iline_amt ($ilines->findnodes('./fund_data/fund_short_data'))
          {
               #If going to do math on the value then do findvalue->value() or get a no method found error
               $il_amt = $iline_amt->findvalue( './amount/sum')->value();
               $amt = sprintf("%.2f", $il_amt);

               $fund_code = $iline_amt->findvalue( './fund_code');

               #print ("\nInv Line No: $inv_line_no\n");
               #print ("Obj_code: $budget_code\n");
               #print ("Amount: $amt\n");
               #print ("Fund Code: $fund_code\n");

               #Validate the object (budget) code. If its missing throw it back.
               if ($budget_code ne "64801" && $budget_code ne "64802" && $budget_code ne "64803" && $budget_code ne "64804" && $budget_code ne "64805" && $budget_code ne "64806" &&
                   $budget_code ne "64807" && $budget_code ne "64808" && $budget_code ne "64809" && $budget_code ne "64810" && $budget_code ne "64811" && $budget_code ne "64812" &&
                   $budget_code ne "64813" && $budget_code ne "64814" && $budget_code ne "64815" && $budget_code ne "64816" && $budget_code ne "64817" && $budget_code ne "64818" &&
                   $budget_code ne "64819" && $budget_code ne "64820")
               {
                    print OUT_LOG ("\nObject code missing or invalid for invoice $inv_no line number $inv_line_no. Please resolve.\n");
                    return;
               }

               for ($j = 0; $j < $i; $j++)
               {
                    if ($funds[$j] eq $fund_code)
                    { 
			if ($amts_budget[$j] > 0)
                        {
			     $amts_budget[$j] = $amts_budget[$j] + $amt;
                        }
                        else
                        {
			     $amts_budget[$j] = $amt;
                        }

                        $len = length($budget_code);
                        if ($len > 0)
                        {
                             $reporting_codes[$j] = $budget_code;
                        }
                    }
               }                  

          }
     }

     #Set up the object code description for the voucher line. This only gets sent once per invoice so just grab last one if more than one invoice line
     if ($i > 0)
     {
	  $j = $i - 1;
     }
     else
     {
	  $j = 0;
     }

     for ($k = 0; $k <= $#obj_code; $k++)
     {
          if ($reporting_codes[$j] eq $obj_code[$k])
          {
               $desc = sprintf("%-30s", $obj_desc[$k]);
          }
     }

     #Make sure all of the budget lines add up to the invoice total. 
     for ($j = 0, $tot_iline_amts = 0; $j <= $i; $j++)
     {
           $tot_iline_amts = $tot_iline_amts + $amts_budget[$j];                            
     }

     $tot_line_amts = sprintf("%.2f", $tot_iline_amts);

     if ($tot_line_amts != $inv_tot)
     {
           #Keep these in for testing. If off, by how much?
           if ($tot_line_amts > $inv_tot)
           {
	        $dff = $tot_line_amts - $inv_tot;
           }

           if ($tot_line_amts < $inv_tot)
           {
	        $dff = $inv_tot - $tot_line_amts;
           }

           print OUT_LOG ("\nBudget line amounts do not equal invoice total for invoice $vendor_code $inv_no\n");
           return;
     }

     #Build distribution lines. If chart string (ext_budget) or reporting code changes need a new line
     for ($j = 0, $dist_count = 0; $j < $i; $j++)
     {
          if ($dist_budget[$j] eq $ext_budget[$j] && $dist_rc[$j] eq $reporting_codes[$j])
          { 
	       if ($dist_amts[$j] > 0)
               {
	            $dist_amts[$j] = $dist_amts[$j] + $amts_budget[$j];
               }
               else
               {
	            $dist_amts[$j] = $amts_budget[$j];
               }
          }
          else
          {
              if ($dist_count == 0)
              {
	           $dist_budget[$dist_count] = $ext_budget[$j];
	           $dist_rc[$dist_count] = $reporting_codes[$j];
	           $dist_amts[$dist_count] = $amts_budget[$j];
                   $dist_count++;
              }
              else
              {
	           for ($k = 0, $found_it = 0; $k < $dist_count; $k++)
                   {
                        if ($dist_budget[$k] eq $ext_budget[$j] && $dist_rc[$k] eq $reporting_codes[$j])
                        {
	                     if ($dist_amts[$k] > 0)
                             {
	                          $dist_amts[$k] = $dist_amts[$k] + $amts_budget[$j];
                                  $found_it = 1;
                                  $k = $dist_count; #Break out of this loop
                             }
                             else
                             {
	                          $dist_amts[$k] = $amts_budget[$j];
                                  $found_it = 1;
                                  $k = $dist_count; #Break out of this loop
                             }
                        }
                   }
                   
                   if (!$found_it)
                   {
	                 $dist_budget[$dist_count] = $ext_budget[$j];
	                 $dist_rc[$dist_count] = $reporting_codes[$j];
	                 $dist_amts[$dist_count] = $amts_budget[$j];
                         $dist_count++;
                   }
	      }
          }
     }

     #Build the voucher header
     $vhdr = sprintf("%s%s%s%-30s%s%s%s%03d%s%s%s%s", $vrow_id, "EAGLE", "        ", $inv_no, $inv_date, $ps_vendor, "          ", $ps_addr, "00   ", $inv_tott, $inv_discc, "LIB");
     #print ("\nVoucher Header: $vhdr");
     print FEED ("$vhdr\n");

     #Build the voucher line
     $vline = sprintf("%s%s%s%s%s%s", $vlrow_id, "EAGLE", $inv_tott, "00001", $user_vchr_dec, $desc);
     #print ("\nVoucher Line:   $vline");
     print FEED ("$vline\n");

     #Print the distribution lines
     for ($j = 0; $j < $dist_count; $j++)
     {
          $inv_tott = &format_ps_money($dist_amts[$j]);

	  @chart_str = split (/-/, $dist_budget[$j]);
          $dept = sprintf("%-10s", $chart_str[0]); 
          $fund_code = sprintf ("%-5s", $chart_str[1]);
          $fund_src = sprintf ("%-10s", $chart_str[2]);
          $prog_code = sprintf ("%-5s", $chart_str[3]);
          $ps_func = sprintf ("%-10s", $chart_str[4]);
          $prop = "00000     ";

          #Distribution lines are numbered 1 to n so add 1 to j here.
	  $dline = sprintf("%s%s%s%05d%s%s%s%s%s%s%-10s%s", $dlrow_id, "EAGLE", "00001", ($j+1), $fund_code, $fund_src, $dept, $prog_code, $prop, $ps_func, $dist_rc[$j], $inv_tott);
          #print ("\n$dline"); 
          print FEED ("$dline\n");
     }

     $no_sent++;

     return;
}


#This subroutine formats the money going into the peoplesoft feed into a signed 28 char string with 3 decimal places
#Example: -00000000000000000000123.600 is the amount $123.60
sub format_ps_money
{

    my ($amt) = @_;

    my (@v1, $dpart, $cpart1, $cpart, $len, $ret_amt);

    @v1 = split(/\./, $amt);

    $dpart = $v1[0];
    $cpart = $v1[1];

    $len = length($dpart);
    if ($len <= 0)
    {
	$dpart = 0;
    }

    $len = length($cpart);
    if ($len <= 0)
    {
	$cpart1 = 0;
        $cpart = sprintf("%03d", $cpart1);
    }
    elsif ($len == 1)
    {
	$cpart1 = $cpart;
        $cpart = sprintf("%s%s", $cpart1, "00");
    }
    elsif ($len == 2)
    {
	$cpart1 = $cpart;
        $cpart = sprintf("%s%s", $cpart1, "0");
    }
    
    $ret_amt = sprintf("%024d%s%s", $dpart, ".", $cpart);

    return ($ret_amt);

}


sub ps_connection
{
     my ($ftp);

     #FTP to PeopleSoft production server
     if ($ftp = Net::FTP->new("someserver.bc.edu", Debug => 0))
     {
          if ($ftp->login("username", "password"))
          {
               $ftp->binary;
               if ($ftp->cwd("Library"))
               {
                    return($ftp);
	       }
          }
     }

     $ftp->quit;
}

sub send_log
{
     my($logfn) = @_;

     $email_sender = "Boston College Library";
     $email_subject = "Log: Alma Invoice feed to PeopleSoft";
     $recipient = "briandwo\@bc.edu";

     #Open output log 
     $ret = open(LOG_IN, $logfn);
     if ($ret < 1)
     {
          die ("Cannot open log file $logfn");
          exit;
     }

     @msg_text = <LOG_IN>;

     $msg = MIME::Lite->new(
                           From => "$email_sender",
                           To => "$recipient",
                           Subject => "$email_subject",
                           Datestamp => 'true',
                           Date => "",
                           Data => "@msg_text"
                           );
     $msg->send;
}

#Convert the month (mm) to a 3 char mon
#Where mon is jan, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec
sub get_mon_component
{
   
    my ($dmon) = @_;

    if ($dmon eq "1")
    {
	$wd_mon = "Jan";
    }
    elsif ($dmon eq "2")
    {
	$wd_mon = "Feb";
    }
    elsif ($dmon eq "3")
    {
	$wd_mon = "Mar";
    }
    elsif ($dmon eq "4")
    {
	$wd_mon = "Apr";
    }
    elsif ($dmon eq "5")
    {
	$wd_mon = "May";
    }
    elsif ($dmon eq "6")
    {
	$wd_mon = "Jun";
    }
    elsif ($dmon eq "7")
    {
	$wd_mon = "Jul";
    }
    elsif ($dmon eq "8")
    {
	$wd_mon = "Aug";
    }
    elsif ($dmon eq "9")
    {
	$wd_mon = "Sep";
    }
    elsif ($dmon eq "10")
    {
	$wd_mon = "Oct";
    }
    elsif ($dmon eq "11")
    {
	$wd_mon = "Nov";
    }
    elsif ($dmon eq "12")
    {
	$wd_mon = "Dec";
    }
    else
    {
        $wd_mon = "error";
    }

    return ($wd_mon);   
}
