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
        return FamilyCallConnection(
            applicationContext,
            data,
            TelecomCallManager.isSelfManagedPhoneAccount(connectionManagerPhoneAccount),
        )
    }

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle,
        request: ConnectionRequest,
    ) {
        val data = TelecomCallManager.callDataFromRequest(request)
        if (isIncomingCallPush(data)) {
            TelecomCallManager.showIncomingCallFallback(this, data)
            return
        }
        TelecomCallManager.rejectIncomingCall(applicationContext, data)
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
