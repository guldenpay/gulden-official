// AUTOGENERATED FILE - DO NOT MODIFY!
// This file generated by Djinni from libunity.djinni

package unity_wallet.jniunifiedbackend;

/** Monitoring events */
public abstract class MonitorListener {
    public abstract void onPartialChain(int height, int probableHeight, int offset);

    public abstract void onPruned(int height);

    public abstract void onProcessedSPVBlocks(int height);
}