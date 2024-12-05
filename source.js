const ethers = await import('npm:ethers@5.7.0');
const Anthropic = await import('npm:@anthropic-ai/sdk');
const decoder = new ethers.utils.AbiCoder();
const proposion = args[1];
let articles = decoder.decode(['string[]'],bytesArgs[0])[0];
articles = articles.map((post) => `- ${post}\n`).join('\n');
const prompt = args[0];
const anthropic = new Anthropic.Anthropic({apiKey: secrets.apiKey});

let response;
try {
    response = await anthropic.messages.create({
        model: 'claude-3-sonnet-20240229',
        max_tokens: 1000,
        temperature: 0,
        messages: [{
            role: 'user',
            content: [{
                type: 'text',
                text: prompt.replace('{{ARTICLES}}', articles)
            }]
        }]
    });
} catch(e) {
    response = { content: [{ text: 'Error calling Anthropic API' }] };
}

function extractTagContent(xml, tagName) {
    const startTag = `<${tagName}>`;
    const endTag = `</${tagName}>`;
    const startIndex = xml.indexOf(startTag);
    const endIndex = xml.indexOf(endTag, startIndex + startTag.length);
    if (startIndex === -1 || endIndex === -1) {
        return '';
    }
    return xml.slice(startIndex + startTag.length, endIndex);
}


const result = response.content[0].text;
const resultString = extractTagContent(result, 'final_answer');

return Functions.encodeString(resultString);