// no need to retry for timeout, network sends packets all the time and finally ends with an error time out, and next restart it.
	fsm.addStateAction( bsrnchlConnecting,  ConnectingSocketChannel::startConnecting,  false );
	fsm.add( bsrnchlConnecting, levsig_stop,         bsrnchlStopped,    ConnectingSocketChannel::closeSocket ); // close it
	fsm.add( bsrnchlConnecting, levsig_start,        bsrnchlConnecting, fsm.Empty );
	fsm.add( bsrnchlConnecting, levsig_connected,    bsrnchlConnected,  fsm.Empty );
	fsm.add( bsrnchlConnecting, levsig_accepted,     bsrnchlConnected,  fsm.Empty );
	fsm.add( bsrnchlConnecting, levsig_failed,       bsrnchlFailed,     fsm.Empty );
	fsm.add( bsrnchlConnecting, levsig_disconnected, bsrnchlFailed,     fsm.Empty );
	fsm.add( bsrnchlConnecting, levsig_timeout,      bsrnchlConnecting, ConnectingSocketChannel::startRestartConnecting );

	fsm.addStateAction( bsrnchlFailed,  ConnectingSocketChannel::closeSocket,  false );
	fsm.add( bsrnchlFailed, levsig_stop,         bsrnchlStopped,    fsm.Empty ); // close it
	fsm.add( bsrnchlFailed, levsig_start,        bsrnchlFailed,     fsm.Empty );
	fsm.add( bsrnchlFailed, levsig_connected,    bsrnchlConnected,  fsm.Empty ); // this is not expected
	fsm.add( bsrnchlFailed, levsig_accepted,     bsrnchlConnected,  fsm.Empty ); // this is not expected
	fsm.add( bsrnchlFailed, levsig_failed,       bsrnchlFailed,     fsm.Empty );
	fsm.add( bsrnchlFailed, levsig_disconnected, bsrnchlFailed,     fsm.Empty );
	fsm.add( bsrnchlFailed, levsig_timeout,      bsrnchlConnecting, fsm.Empty );

	fsm.addStateAction( bsrnchlConnected,  ConnectingSocketChannel::startProtocolCommunication,  true );
	fsm.add( bsrnchlConnected, levsig_stop,          bsrnchlStoppingRequest,    fsm.Empty ); // close it
	fsm.add( bsrnchlConnected, levsig_start,         bsrnchlConnected,  fsm.Empty );
	fsm.add( bsrnchlConnected, levsig_connected,     bsrnchlConnected,  fsm.Empty );
	fsm.add( bsrnchlConnected, levsig_accepted,      bsrnchlConnected,  fsm.Empty );
	fsm.add( bsrnchlConnected, levsig_failed,        bsrnchlFailed,     fsm.Empty );
	fsm.add( bsrnchlConnected, levsig_disconnected,  bsrnchlFailed,     fsm.Empty );
	fsm.add( bsrnchlConnected, levsig_timeout,       bsrnchlConnected,  fsm.Empty );
	fsm.add( bsrnchlConnected, levsig_handshakeDone, bsrnchlEstablishedSuccess, fsm.Empty );
	fsm.add( bsrnchlConnected, levsig_handshakeFailed, bsrnchlFailed,   fsm.Empty );

	fsm.add( bsrnchlEstablishedSuccess, levsig_stop,          bsrnchlStoppingRequest,    fsm.Empty ); // close it
	fsm.add( bsrnchlEstablishedSuccess, levsig_start,         bsrnchlEstablishedSuccess, fsm.Empty );
	fsm.add( bsrnchlEstablishedSuccess, levsig_connected,     bsrnchlEstablishedSuccess, fsm.Empty );
	fsm.add( bsrnchlEstablishedSuccess, levsig_accepted,      bsrnchlEstablishedSuccess, fsm.Empty );
	fsm.add( bsrnchlEstablishedSuccess, levsig_failed,        bsrnchlFailed,             fsm.Empty );
	fsm.add( bsrnchlEstablishedSuccess, levsig_disconnected,  bsrnchlFailed,             fsm.Empty );
	fsm.add( bsrnchlEstablishedSuccess, levsig_timeout,       bsrnchlEstablishedSuccess, fsm.Empty );
	fsm.add( bsrnchlEstablishedSuccess, levsig_handshakeDone, bsrnchlEstablishedSuccess, fsm.Empty );