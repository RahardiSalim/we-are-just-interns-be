package com.gosafe.gosafe

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * AES-256-GCM for ride recordings at rest. The key lives in the Android Keystore and never leaves it,
 * so the file is useless if copied off the phone. File format: 12-byte IV, then ciphertext + tag.
 */
object Vault {
    private const val ALIAS = "gosafe-recording"
    private const val IV = 12

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as SecretKey?)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(
                KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build(),
            )
        }.generateKey()
    }

    /** Writes `bytes` encrypted to `path` (via a temp file, so a crash never leaves half a file). */
    fun seal(path: String, bytes: ByteArray) {
        val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val tmp = File("$path.tmp")
        tmp.outputStream().use { it.write(c.iv); it.write(c.doFinal(bytes)) }
        tmp.renameTo(File(path))
    }

    fun open(path: String): ByteArray {
        val b = File(path).readBytes()
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, b, 0, IV))
        return c.doFinal(b, IV, b.size - IV)
    }
}
