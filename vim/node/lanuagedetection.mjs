import pkg from '@vscode/vscode-languagedetection'
import * as readline from 'readline'

const { ModelOperations } = pkg

function readStdin() {
    return new Promise((resolve, reject) => {
        const rl = readline.createInterface({
            input: process.stdin,
            output: process.stdout,
            terminal: false
        })

        let data = ''
        rl.on('line', (line) => {
            data += line + '\n'
        })

        rl.on('close', () => {
            resolve(data)
        })

        rl.on('error', (err) => {
            reject(err)
        })
    })
}

async function main() {
    let content = await readStdin()
    const modulOperations = new ModelOperations()
    const result = await modulOperations.runModel(content)
    process.stdout.write(result[0].languageId)
}

main()
