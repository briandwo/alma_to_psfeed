# alma_to_psfeed
Ex Libris' Alma files for PeopleSoft feed


I have attached 4 files: 
1)	the perl script (renamed to alma_to_psfeed.mbw instead of alma_to_psfeed.pl in case you want to email it. Save this file as alma_to_psfeed.pl
2)	alma_invoice_20130726.xml (this is a sample of the invoice data exported from Alma. Note that Alma does not name the file something this coherent, I have renamed the file. Alma names it a bunch of meaningless numbers.  The fields exported are not configurable, Ex Libris has chosen what data to export. The format is not configurable either, the only output format is XML)
3)	a sample of the output file that we FTP to our PeopleSoft server 
                The output file consists of the following for each invoice:
    1 voucher header
    1 voucher line
    1 to many distribution lines
4)	PS_INVOICES Alma Setup Screens

It is best if you open the perl script in an editor (such as vi or emacs) or it will be a jumble and hard to read.
I open the XML files exported by Alma using Oxygen.

To configure Alma to export your invoices go to:
General Configuration -> Configuration Menu -> Under External Systems click on Integration Profiles -> Add External System for code PS_INVOICES
I have attached our setup screens from Alma.

