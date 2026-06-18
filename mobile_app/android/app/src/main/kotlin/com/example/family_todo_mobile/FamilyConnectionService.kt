package com.example.family_todo_mobile

import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle

class FamilyConnectionService : ConnectionService() {
    override fun onCreate() {
        super.onCreate()
        TelecomCallManager.registerPhoneAccounts(this)
    }

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle,
        request: ConnectionRequest,
    ): Connection {
        val data = TelecomCallManager.callDataFromRequest(request)
        return FamilyCallConnection(applicationContext, data)
    }

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle,
        request: ConnectionRequest,
    ) {
        TelecomCallManager.rejectIncomingCall(
            applicationContext,
            TelecomCallManager.callDataFromRequest(request),
        )
    }

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle,
        request: ConnectionRequest,
    ): Connection {
        return Connection.createFailedConnection(
            DisconnectCause(DisconnectCause.ERROR, "Outgoing calls start in Flutter")
        )
    }
}
