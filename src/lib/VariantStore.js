.pragma library

function saveVariant(store, msgId, index, variant, maxVariants) {
    if (!store[msgId]) store[msgId] = [];
    var saved = {
        content: variant.content || "",
        thinking: variant.thinking || "",
        modelName: variant.modelName || ""
    };
    if (variant.errorText)
        saved.errorText = variant.errorText;
    store[msgId][index] = saved;

    var evicted = 0;
    while (store[msgId].length > maxVariants) {
        store[msgId].shift();
        evicted++;
    }

    return { store: store, evicted: evicted };
}

function getVariant(store, msgId, index) {
    if (!store[msgId] || index >= store[msgId].length || !store[msgId][index])
        return null;
    return store[msgId][index];
}

function adjustAfterEviction(evicted, currentVariantIndex, storeLength, isStreamingThisMsg) {
    var newIndex = Math.max(0, Math.min(currentVariantIndex - evicted, storeLength - 1));
    var logicalCount = isStreamingThisMsg ? storeLength + 1 : storeLength;
    return { variantIndex: newIndex, variantCount: logicalCount };
}
