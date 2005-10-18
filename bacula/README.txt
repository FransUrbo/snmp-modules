1. Add in 'Data Templates':
   a) Primary values:
      Data Template Name:		SNMP - Local - Bacula Statistics
      Data Source Name:			|host_description| - Bacula Statistics
      Data Input Method:		Get SNMP Data (Indexed)
      Internal Data Source Name:	bytes
      Minimum Value:			0
      Maximum Value:			100000000
      Data Source Type:			ABSOLUTE
      Heartbeat:			600

   b) Add new 'Data Source Item'
      Internal Data Source Name:	duration
      Minimum Value:			0
      Maximum Value:			100000000
      Data Source Type:			ABSOLUTE
      Heartbeat:			600

   *) Do point 1b two more times. Once for files and once for missing.

2. Add in 'Graph Templates':
   a) Primary values:
      Name:				SNMP - Local - Bacula Statistics
      Title:				|query_baculaClientName| - Bacula Statistics
      Upper Limit:			100000000
      Vertical Label:			Client name
      [rest of the values - use defaults]

   b) Add in 'Graph Template Items' for the 'SNMP - Local - Bacula Statistics' graph template:
      Data Source:			SNMP - Local - Bacula Statistics - (bytes)
      Color:				C4FD3D
      Graph Item Type:			AREA
      Consolidation Function:		AVERAGE
      CDEF Function:			NONE
      Value:				<empty>
      GPRINT Type:			Normal
      Text Format:			Bytes
      Insert Hard Return:		No

   c) Add in 'Graph Template Items' for the 'SNMP - Local - Bacula Statistics' graph template:
     Data Source:			SNMP - Local - Bacula Statistics - (bytes)
      Color:				None
      Graph Item Type:			GPRINT
      Consolidation Function:		LAST
      CDEF Function:			NONE
      Value:				<empty>
      GPRINT Type:			Normal
      Text Format:			Current:
      Insert Hard Return:		No

   d) Add in 'Graph Template Items' for the 'SNMP - Local - Bacula Statistics' graph template:
      Data Source:			SNMP - Local - Bacula Statistics - (bytes)
      Color:				None
      Graph Item Type:			GPRINT
      Consolidation Function:		AVERAGE
      CDEF Function:			NONE
      Value:				<empty>
      GPRINT Type:			Normal
      Text Format:			Average:
      Insert Hard Return:		No

   e) Add in 'Graph Template Items' for the 'SNMP - Local - Bacula Statistics' graph template:
      Data Source:			SNMP - Local - Bacula Statistics - (bytes)
      Color:				None
      Graph Item Type:			GPRINT
      Consolidation Function:		MAX
      CDEF Function:			NONE
      Value:				<empty>
      GPRINT Type:			Normal
      Text Format:			Maximum:
      Insert Hard Return:		Yes, ticked!

   *) Do points 2b to 2e three more times. Once for the duration, once for the files, once for
      files and once for missing!

   => With this, you should end up with the following graph template definition:
	* Graph Template Items [edit: SNMP - Local - Bacula Statistics] Add  
 
	  Graph Item  Data Source  Graph Item Type  CF Type  Item Color  
	  Item # 1  (bytes): Bytes	     AREA     AVERAGE   C4FD3D    
	  Item # 2  (bytes): Current:	     GPRINT   LAST       
	  Item # 3  (bytes): Average:	     GPRINT   AVERAGE       
	  Item # 4  (bytes): Maximum:<HR>    GPRINT   MAX       
	  Item # 5  (duration): Duration     AREA     AVERAGE   FFF200    
	  Item # 6  (duration): Current:     GPRINT   LAST       
	  Item # 7  (duration): Average:     GPRINT   AVERAGE       
	  Item # 8  (duration): Maximum:<HR> GPRINT   MAX       
	  Item # 9  (files): Files	     AREA     AVERAGE   4444FF    
	  Item # 10 (files): Current:	     GPRINT   LAST       
	  Item # 11 (files): Average:	     GPRINT   AVERAGE       
	  Item # 12 (files): Maximum:	     GPRINT   MAX       
	  Item # 13 (missing): Missing	     LINE3    AVERAGE   FF0000    
	  Item # 14 (missing): Current:	     GPRINT   LAST       
	  Item # 15 (missing): Average:	     GPRINT   AVERAGE       
	  Item # 16 (missing): Maximum:<HR>  GPRINT   MAX       
 
	* Graph Item Inputs Add  
	  Name  
	  Data Source [bytes]    
	  Data Source [duration]    
	  Data Source [files]    
	  Data Source [missing]    

3. Add in 'Data Queries':
   a) Name:				SNMP - Local - Bacula Statistics
   b) Description:			Bacula statistics
   c) XML Path:				<path_cacti>/resource/snmp_queries/bacula-stats.xml
   d) Data Input Method:		Get SNMP Data (Indexed)
   e) Add 'Associated Graph Templates'
      a) Name:				SNMP - Local - Bacula Statistics
      b) Graph Template:		SNMP - Local - Bacula Statistics
